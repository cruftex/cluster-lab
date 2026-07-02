

PROXY_BUMP_CA_CRT=/etc/squid/ssl/ssl-bump-ca.crt
# Empty means bin/lab derives the prefix from the lab project directory name.
LAB_PREFIX="${LAB_PREFIX:-}"
POOL=default
NET_NAME=lc
NET_DOMAIN=k8s.local
# Empty means bin/lab derives or allocates the prefix for this lab.
NET_PREFIX="${NET_PREFIX:-}"
NET_PREFIX_POOL_BASE="${NET_PREFIX_POOL_BASE:-192.168}"
NET_PREFIX_POOL_START="${NET_PREFIX_POOL_START:-120}"
NET_PREFIX_POOL_END="${NET_PREFIX_POOL_END:-199}"
OSVAR=ubuntu24.04
DISK_G=20
BASE_URL=https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
BASE_VOL=noble-server-cloudimg-amd64.img
# minimal image does not startup, needs debugging
# BASE_URL=https://cloud-images.ubuntu.com/minimal/releases/noble/release-20260128/ubuntu-24.04-minimal-cloudimg-amd64.img
# BASE_VOL=ubuntu-24.04-minimal-base.qcow2
BASE_USER=ubuntu

# Optional SSH key for cloud-init
SSH_PUBKEY="${SSH_PUBKEY:-}"

for k in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
  [[ -z "$SSH_PUBKEY" && -f "$k" ]] && {
    SSH_PUBKEY="$(<"$k")";
  }
done

declare -gA NODES=(
  [cp1]="4096 2 seed"
  [wk1]="3072 2 wk"
  [wk2]="3072 2 wk"
  [wk3]="3072 2 wk"
)
declare -gA SYNC_DIRS=()

SSH_PUBKEY_PATH=""
KUBE_VERSION=1.34.3
NODE_SETUP=apt-containerd
SEED_SETUP=calico

NET_ADDR=
NET_MASK=
NET_PREFIX_LEN=
DHCP_START=
DHCP_END=
