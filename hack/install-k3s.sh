#!/usr/bin/env bash
# Install single-node k3s on a Linux host (any VM, bare metal, arm64 or amd64)
# the way the lean profile expects (zero-cost-mvp.md §3): Traefik off (Caddy
# is the ingress), ServiceLB on (binds 80/443 for Caddy), local-path storage.
#
#   sudo hack/install-k3s.sh                 # install k3s
#   make gitops CLUSTER=free                 # then let Flux deploy Fibrik
set -euo pipefail

K3S_VERSION=${K3S_VERSION:-v1.37.1+k3s1}

if [[ $EUID -ne 0 ]]; then
  echo "run as root (sudo)" >&2
  exit 1
fi

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="$K3S_VERSION" \
  INSTALL_K3S_EXEC="server --disable=traefik --write-kubeconfig-mode=0640" \
  sh -

echo "waiting for the node to be Ready"
k3s kubectl wait --for=condition=Ready node --all --timeout=180s
echo "k3s $K3S_VERSION is running. Kubeconfig: /etc/rancher/k3s/k3s.yaml"
