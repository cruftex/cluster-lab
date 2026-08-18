set -e
export KUBECONFIG=/etc/kubernetes/admin.conf



# install cert-manager
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/v1.20.3/cert-manager.yaml"

# Wait for the webhook to be available
kubectl wait --timeout=5m -n cert-manager \
  --for=condition=Available deployment/cert-manager-webhook

# Wait for CA injection to complete
until [ -n "$(kubectl get validatingwebhookconfiguration cert-manager-webhook \
  -o jsonpath='{.webhooks[0].clientConfig.caBundle}')" ]; do
    sleep 1
done

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


