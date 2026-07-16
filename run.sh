#!/bin/sh
# Ticket 10 (real-estate): "would the estate pass vNext?" -- offline by
# construction. Never touches admission, installs no shadow policies,
# pollutes no live PolicyReports: everything here is kyverno apply against
# a local dump of live workload manifests, never `kubectl apply`.
#
# Mechanism (fact-checked live, 2026-07-16, against real kyverno CLI
# 1.18.2 and the real require-department-label policy + fixtures):
#   1. Clone the candidate version's tag from the policy repo.
#   2. Render each of that tag's policies via kustomize (keeps the
#      nameSuffix/labels), then strip matchConditions (the version-scope
#      CEL gate) via `yq del` -- "evaluate everyone as if opted in".
#   3. Dump every live workload carrying mycompany.com/policy-version, one
#      resource per file (kyverno apply silently produces nothing against
#      a `kind: List`-wrapped multi-doc file -- found live, not assumed).
#   4. kyverno apply the stripped policies against the dump,
#      --policy-report --output-format json. Exits 1 on any fail (CI-gate
#      semantics) -- capture and parse the JSON regardless of exit code.
#   5. Group results by team (the `app` label already on every workload,
#      set by that team's own k8s/deployment.yaml), publish per-team
#      pass/fail counts + a ready boolean to a ConfigMap.
set -eu
WORK=${WORK:-/work}
POLICY_URL=${POLICY_URL:-https://github.com/policy-as-versioned-flux/policy}
CANDIDATE_TAG=${CANDIDATE_TAG:?CANDIDATE_TAG required, e.g. 2.2.0}
CANDIDATE_VERSION=${CANDIDATE_VERSION:-$CANDIDATE_TAG}
NAMESPACE=${NAMESPACE:-monitoring}
mkdir -p "$WORK"
cd "$WORK"

echo "== clone candidate tag v$CANDIDATE_TAG =="
rm -rf policy
git clone -q --branch "v$CANDIDATE_TAG" "$POLICY_URL" policy

echo "== render + strip matchConditions from every policy in this tag =="
mkdir -p policies-stripped
for dir in policy/workloads/kyverno/*/ policy/cloud/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  kustomize build "$dir" | yq eval 'del(.spec.matchConditions)' - > "policies-stripped/$name.yaml"
done

echo "== dump live workloads carrying mycompany.com/policy-version, one resource per file =="
rm -rf resources && mkdir -p resources
kubectl get pods -A -l 'mycompany.com/policy-version' -o json \
  | yq -o=json '.items[]' - | jq -c '.' \
  | nl -ba | while read -r n line; do
      echo "$line" | yq -P > "resources/pod-$n.yaml"
    done
resource_count=$(find resources -type f | wc -l)
echo "  $resource_count live workloads dumped"

echo "== kyverno apply: evaluate every workload against the candidate version's stripped policies =="
kyverno apply policies-stripped --resource resources --policy-report --output-format json > report.json 2>report.err || true
[ -s report.json ] || { echo "FAIL: kyverno apply produced no report"; cat report.err; exit 1; }

echo "== group by team (the app label), publish per-team pass/fail + readiness =="
for f in resources/*.yaml; do
  yq -o=json '{"name": .metadata.name, "app": .metadata.labels.app}' "$f"
done | jq -s '.' > name-to-app.json

teams_json=$(jq -c --slurpfile resfiles name-to-app.json '
  . as $report
  | ($resfiles[0] | map({(.name): .app}) | add) as $name_to_app
  | [$report.results[]
     | .resources[0].name as $rname
     | {team: ($name_to_app[$rname] // "unknown"), result: .result}]
  | group_by(.team)
  | map({
      key: .[0].team,
      value: {
        pass: (map(select(.result == "pass")) | length),
        fail: (map(select(.result == "fail")) | length)
      }
    })
  | from_entries
  | with_entries(.value.ready = (.value.fail == 0))
' report.json)

payload=$(jq -n --arg v "$CANDIDATE_VERSION" --arg t "$CANDIDATE_TAG" --argjson teams "$teams_json" \
  '{candidate_version: $v, candidate_tag: $t, teams: $teams}')
echo "$payload" > readiness.json
echo "$payload" | jq .

echo "== publish as a ConfigMap for the estate dashboard to read =="
kubectl create configmap "readiness-$CANDIDATE_VERSION" -n "$NAMESPACE" \
  --from-file=readiness.json=readiness.json \
  --dry-run=client -o yaml | kubectl apply -f -

not_ready=$(echo "$teams_json" | jq '[.[] | select(.ready == false)] | length')
echo "== done: candidate $CANDIDATE_VERSION, $not_ready team(s) not ready =="
