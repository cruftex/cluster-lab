
set -e

export KUBECONFIG=/etc/kubernetes/admin.conf

curl -sS -O https://raw.githubusercontent.com/projectcalico/calico/v3.31.3/manifests/calico.yaml

# downloading from quay.io fails
# TODO: Calico images are officially hosted on quay.io, however, we get 403 from there
sed -i 's|quay.io/|docker.io/|g' calico.yaml

kubectl apply -f calico.yaml

# wait for CRD
kubectl wait --for condition=Established crd/felixconfigurations.crd.projectcalico.org --timeout=60s

#until kubectl api-resources | grep -q '^felixconfigurations'; do
#  echo "waiting for FelixConfiguration API..."
#  sleep 2
#done


# Switch on wireguard encryption
# Its a common pattern that internal cluster traffic is unencrypted (http instead of https)
# With this setting we encrypt all internal traffic leaving a node

cat >> calico-wireguard.yaml <<'EOF'
---
apiVersion: crd.projectcalico.org/v1
kind: FelixConfiguration
metadata:
  name: default
spec:
  wireguardEnabled: true
  wireguardEnabledV6: true
EOF

kubectl apply -f calico-wireguard.yaml
