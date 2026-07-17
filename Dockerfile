# Ticket 10 (real-estate): pinned toolchain, same governed-dependency
# posture as every other component here (checksummed binaries, no
# marketplace actions / unpinned apk packages for the tools that matter).
FROM alpine:3.24
RUN apk add --no-cache git jq curl bash

ARG KYVERNO_VERSION=1.18.2
ARG KYVERNO_SHA256=cb2feb8356149fd2fe774c894ccf0969f4a60a83867dd913af724f74ffbbc18b
ARG KUSTOMIZE_VERSION=5.8.1
ARG KUSTOMIZE_SHA256=029a7f0f4e1932c52a0476cf02a0fd855c0bb85694b82c338fc648dcb53a819d
ARG KUBECTL_VERSION=1.31.4
ARG YQ_VERSION=4.44.3
ARG YQ_SHA256=a2c097180dd884a8d50c956ee16a9cec070f30a7947cf4ebf87d5f36213e9ed7

RUN set -eu; \
    curl -sSL -o kyverno.tar.gz "https://github.com/kyverno/kyverno/releases/download/v${KYVERNO_VERSION}/kyverno-cli_v${KYVERNO_VERSION}_linux_x86_64.tar.gz"; \
    echo "${KYVERNO_SHA256}  kyverno.tar.gz" | sha256sum -c -; \
    tar xzf kyverno.tar.gz kyverno && chmod +x kyverno && mv kyverno /usr/local/bin/kyverno; \
    rm kyverno.tar.gz; \
    \
    curl -sSL -o kustomize.tar.gz "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz"; \
    echo "${KUSTOMIZE_SHA256}  kustomize.tar.gz" | sha256sum -c -; \
    tar xzf kustomize.tar.gz kustomize && chmod +x kustomize && mv kustomize /usr/local/bin/kustomize; \
    rm kustomize.tar.gz; \
    \
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/'); \
    curl -sSLo kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"; \
    curl -sSLo kubectl.sha256 "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl.sha256"; \
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c -; \
    chmod +x kubectl && mv kubectl /usr/local/bin/kubectl; \
    rm kubectl.sha256; \
    \
    curl -sSL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64"; \
    echo "${YQ_SHA256}  /usr/local/bin/yq" | sha256sum -c -; \
    chmod +x /usr/local/bin/yq

COPY run.sh /usr/local/bin/run.sh
RUN chmod +x /usr/local/bin/run.sh
ENTRYPOINT ["/usr/local/bin/run.sh"]
