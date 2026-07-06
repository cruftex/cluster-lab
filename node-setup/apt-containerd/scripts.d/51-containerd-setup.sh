
set -e

# Registry proxy
#
registries=`cat - <<EOF
https://registry.internal:5000 docker.io
https://registry.internal:5001 registry.k8s.io
https://registry.internal:5002 quay.io
https://registry.internal:5003 public.ecr.aws
https://registry.internal:5004 codeberg.org
https://registry.internal:5005 ghcr.io
EOF`

mirror=https://registry.internal:5001
if curl -sS -o /dev/null --max-time 3 "$mirror"/v2/ 2>/dev/null; then

echo "$registries" | while read server registry; do
  hosts=/etc/containerd/certs.d/$registry/hosts.toml
  mkdir -p $(dirname "$hosts")
  cat - > $hosts <<EOF
# configured by cluster-lab 51-containerd-setup.sh

# if this is not specified it would be docker.io
server = "$server"

[host."$server"]
  capabilities = ["pull", "resolve", "push"]
EOF
echo "OCI mirror for $registry -> $server"
done

elif curl -sS -o /dev/null --max-time 3 https://zotregistry.internal:5000/v2/ 2>/dev/null; then

server="https://zotregistry.internal:5000"

# proxy setup for zot
echo "$registries" | while read IGNORE R; do
hosts=/etc/containerd/certs.d/$R/hosts.toml
mkdir -p $(dirname "$hosts")
cat - > $hosts <<EOF
# configured by cluster-lab 51-containerd-setup.sh

# if the proxy registry is not available this will be  a hard fail, no fallback to the origin
# Zot does not support "?ns=", so we need to send the registry within the path
server = "$server/v2/$R"
capabilities = ["pull", "resolve", "push"]
override_path = true

# containerd first requests the host entries and then falls back 
# to the server setting above.
# [host."$server/v2/$R"]
#  capabilities = ["pull", "resolve", "push"]
#  override_path = true
EOF
echo "OCI mirror for $R -> $server"

done
else
  echo "No image mirror detected"
fi

cfg=/etc/containerd/config.toml
cfgNew=$cfg-new

#
# Containerd configuration
#

# Bug in containerd
# https://github.com/containerd/containerd/issues/12636
# Default config line does not work:
#    [plugins.'io.containerd.cri.v1.images'.registry]
#      config_path = '/etc/containerd/certs.d:/etc/docker/certs.d'

# Containerd uses cgroupfs driver by default, on systemd system we need to
# switch to systemd cgroup driver, so containerd and kubelet are using
# the same cgroup driver
# https://kubernetes.io/docs/setup/production-environment/container-runtimes/#cgroupfs-cgroup-driver

mkdir -p /etc/containerd
containerd config default | tee $cfg-default \
  | sed 's/SystemdCgroup = false/SystemdCgroup = true/' \
  | sed 's^/etc/containerd/certs.d:/etc/docker/certs.d^/etc/containerd/certs.d^' > $cfgNew

if cmp --quiet $cfg $cfgNew; then
  exit 0
fi

mv $cfgNew $cfg

systemctl enable containerd
systemctl restart containerd

exit 0

# testing

# ctr does not use containerd config:
ctr image pull docker.io/library/alpine:latest
ctr image pull --hosts-dir /etc/containerd/certs.d -- docker.io/library/alpine:latest

kubeadm config images pull --kubernetes-version "v${KUBE_VERSION#v}"
crictl pull docker.io/library/alpine:latest

