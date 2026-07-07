# Install ArgoCD and configure it to get configuration data
# from the git server on cp1

# https://argo-cd.readthedocs.io/en/stable/getting_started/

# Latest releases:
# https://github.com/argoproj/argo-cd/releases

# non HA or HA?
# - Non-HA has automatic recovery after a node failure after a timeout of 40-50 seconds via Kubernetes CP
# - HA has minimal downtime rather than waiting for pods to be rescheduled.

ARGOCD_VERSION=v3.4.4
ARGOCD_NS=argocd

curl -fsSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/$ARGOCD_VERSION/argocd-linux-amd64
install -m 555 argocd-linux-amd64 /usr/local/bin
rm argocd-linux-amd64

kubectl create namespace "$ARGOCD_NS"
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml


# switch to insecure, because ingress terminates https
# TODO: can we patch the initial yaml?
kubectl -n "$ARGOCD_NS" patch configmap argocd-cmd-params-cm \
  --type merge \
  -p '{"data":{"server.insecure":"true"}}'

kubectl -n "$ARGOCD_NS" rollout restart deploy/argocd-server

# The CLI does not work via http, to script the bootstrap we configure via kubectl

#
# Wait for rollout 
#
kubectl -n "$ARGOCD_NS" rollout status deploy/argocd-server --timeout=180s
kubectl -n "$ARGOCD_NS" rollout status deploy/argocd-repo-server --timeout=180s

#
# Add node to known hosts
#
IP=$(hostname -I | awk '{print $1}')
REPO_URL=ssh://git@$IP/srv/git/cluster.git
REPO_KEY=/srv/git/.ssh/authorized_keys
(
  kubectl -n argocd get cm argocd-ssh-known-hosts-cm -o jsonpath='{.data.ssh_known_hosts}' 
  ssh-keyscan $I 
) | sort -u -o /tmp/new_known_hosts
kubectl -n argocd create configmap argocd-ssh-known-hosts-cm \
  --from-file=ssh_known_hosts=/tmp/new_known_hosts \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$ARGOCD_NS" create secret generic repo-cluster \
  --from-literal=type=git \
  --from-literal=url="$REPO_URL" \
  --from-file=sshPrivateKey="$REPO_KEY" \
  --dry-run=client -o yaml \
| kubectl label -f - \
  argocd.argoproj.io/secret-type=repository \
  --local -o yaml \
| kubectl apply -f - 

# port forward UI
# kubectl port-forward svc/argocd-server -n argocd 8080:80

# initial admin password
# kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
