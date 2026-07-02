
: "${KUBE_VERSION:=1.34.3}"
kubeadm config images pull --kubernetes-version "v${KUBE_VERSION#v}"
