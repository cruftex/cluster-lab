# Install kubeadm/kubelet/kubectl on ALL nodes
# Ubuntu 24.04 uses the newer Kubernetes packaging repo (pkgs.k8s.io).

# skip if installed before or installed via virt-customize
if command -v kubelet > /dev/null; then
  echo "kubelet present, skipping"
  exit 0
fi

set -e

export DEBIAN_FRONTEND=noninteractive

: "${KUBE_VERSION:=1.34.3}"
repo_version="${KUBE_VERSION%.*}"

apt-get install -yq apt-transport-https ca-certificates curl gpg

mkdir -p /etc/apt/keyrings
rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v$repo_version/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$repo_version/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

apt-get update

apt-get install -yq kubelet kubeadm kubectl
# apt-mark hold kubelet kubeadm kubectl
