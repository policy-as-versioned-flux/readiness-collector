#!/usr/bin/env bash
# Runnable self-check (the established idiom). Proves the core mechanism
# against a real signed tag from the real policy repo -- not a mock --
# without needing a live cluster: a fixture "1.0.0-era" workload (real
# department label, valid; no owner annotation, same shape as the real
# ledger workload today) evaluated against v2.2.0's stripped policies
# should pass the department checks and fail require-owner-annotation --
# exactly the known case ticket 10 names.
set -euo pipefail
for tool in git jq yq kustomize kyverno; do
  command -v "$tool" >/dev/null || { echo "SKIP: $tool not on PATH"; exit 0; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

echo "== clone real v2.2.0 =="
git clone -q --branch v2.2.0 https://github.com/policy-as-versioned-flux/policy policy

echo "== render + strip matchConditions =="
mkdir -p policies-stripped
for dir in policy/workloads/kyverno/*/; do
  name=$(basename "$dir")
  kustomize build "$dir" | yq eval 'del(.spec.matchConditions)' - > "policies-stripped/$name.yaml"
done

echo "== fixture: a 1.0.0-era workload shape (valid department, no owner annotation) =="
mkdir -p resources
cat > resources/fixture-pod.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: fixture-1.0.0-workload
  namespace: default
  labels:
    app: fixture-team
    department: finance
spec:
  containers:
    - name: app
      image: nginx:latest
EOF

echo "== kyverno apply: evaluate the fixture against v2.2.0's stripped policies =="
kyverno apply policies-stripped --resource resources --policy-report --output-format json > report.json 2>report.err || true
[ -s report.json ] || { echo "FAIL: no report produced"; cat report.err; exit 1; }

dept_result=$(jq -r '.results[] | select(.policy == "require-department-label-2.2.0") | .result' report.json)
owner_result=$(jq -r '.results[] | select(.policy == "require-owner-annotation-2.2.0") | .result' report.json)

[ "$dept_result" = "pass" ] || { echo "FAIL: expected department-label pass, got $dept_result"; exit 1; }
echo "OK: valid department label passes v2.2.0's gate, as expected"

[ "$owner_result" = "fail" ] || { echo "FAIL: expected owner-annotation fail, got $owner_result"; exit 1; }
echo "OK: missing owner annotation fails v2.2.0's lane-keeper -- the known 1.0.0-era-workload case"

echo "== verify.sh: PASS =="
echo "(run.sh's live kubectl get + ConfigMap publish path is proven against the real KiND"
echo " cluster separately -- see ticket 10's comments in the hub for that live proof.)"
