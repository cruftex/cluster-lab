set -e
export KUBECONFIG=/etc/kubernetes/admin.conf



# install cert-manager
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/v1.20.3/cert-manager.yaml"

kubectl wait --timeout=5m -n cert-manager \
  --for=condition=Available deployment/cert-manager
kubectl wait --timeout=5m -n cert-manager \
  --for=condition=Available deployment/cert-manager-webhook
kubectl wait --timeout=5m -n cert-manager \
  --for=condition=Available deployment/cert-manager-cainjector

# creating clusterIssuer 
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: lab-ca-issuer
spec:
  ca:
    secretName: lab-ca-key-pair
EOF