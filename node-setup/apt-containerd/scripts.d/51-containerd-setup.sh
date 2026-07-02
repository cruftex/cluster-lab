
set -e

# Registry proxy
#
# https://registry.internal:5000 docker.io mirror
# https://registry.internal:5001 registry.k8s.io mirror
mirror=https://registry.internal:5001

if curl -sS -o /dev/null --max-time 3 "$mirror"/v2/ 2>/dev/null; then

hosts=/etc/containerd/certs.d/docker.io/hosts.toml
mkdir -p $(dirname "$hosts")
cat - > $hosts <<EOF
# if this is not specified it would be docker.io
server = "https://registry.internal:5000"

[host."https://registry.internal:5000"]
  capabilities = ["pull", "resolve", "push"]
EOF

hosts=/etc/containerd/certs.d/registry.k8s.io/hosts.toml
mkdir -p $(dirname "$hosts")
cat - > $hosts <<EOF
# if this is not specified it would be docker.io
server = "https://registry.internal:5001"

[host."https://registry.internal:5001"]
  capabilities = ["pull", "resolve", "push"]
EOF

echo Mirror configured: https://registry.internal:5000 -> docker.io and https://registry.internal:5001 > registry.k8s.io

elif curl -sS -o /dev/null --max-time 3 https://zotregistry.internal:5000/v2/ 2>/dev/null; then
# proxy setup for zot
for R in docker.io k8s.io; do
hosts=/etc/containerd/certs.d/$R/hosts.toml
mkdir -p $(dirname "$hosts")
cat - > $hosts <<EOF
# if this is not specified it would be docker.io
server = "https://zotregistry.internal:5000/v2/$R"

[host."https://zotregistry.internal:5000"]
  capabilities = ["pull", "resolve", "push"]
  override_path = true
EOF
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

ctr image pull docker.io/library/alpine:latest
ctr image pull --hosts-dir /etc/containerd/certs.d -- docker.io/library/alpine:latest
crictl pull docker.io/library/alpine:latest

