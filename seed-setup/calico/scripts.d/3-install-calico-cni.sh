
set -e

export KUBECONFIG=/etc/kubernetes/admin.conf

curl -sS -O https://raw.githubusercontent.com/projectcalico/calico/v3.31.3/manifests/calico.yaml

# downloading from quay.io fails
# TODO: Calico images are officially hosted on quay.io, however, we get 403 from there
sed -i 's|quay.io/|docker.io/|g' calico.yaml

kubectl apply -f calico.yaml
