#!/bin/bash
set -euo pipefail

# set -x

# for every libvirt network install port 80 and port 443 interceptors to
# redirect to the squid proxy

NET="$1"
ACTION="$2"

# extract from XML, we cannot call virsh because we would deadlock
XML="/etc/libvirt/qemu/networks/${NET}.xml"
BRIDGE=$(sed -n "s/.*bridge name='\([^']*\)'.*/\1/p" "$XML" | head -n1)

if [ -z "$BRIDGE" ]; then
    echo "No bridge found for network $NET" >&2
    exit 1
fi

for cmd in iptables ip6tables; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Required command not found: $cmd" >&2
        exit 1
    fi
done

xtra_chain() {
table="$1" # filter or nat
from="$2" # target chain
dest="$3" # destination chain
iptables -t "$table" -N "$dest" 2> /dev/null || true
iptables -t "$table" -F "$dest"
iptables -t "$table" -C "$from" -j "$dest" || iptables -t "$table" -I "$from" 1 -j "$dest"
}

PREROUTING="$NET-prerouting"
INPUT="$NET-input"
FORWARD="$NET-forward"

# for stop we just flush the chains
if [ "$ACTION" = "started" ] || [ "$ACTION" = "stopped" ]; then
  xtra_chain nat PREROUTING "$PREROUTING"
  xtra_chain filter INPUT "$INPUT"
  xtra_chain filter FORWARD "$FORWARD"
fi

registry_ip=$(getent hosts registry.local | awk '{print $1}' || true)

# action might be: start started port-created stopped
if [ "$ACTION" = "started" ]; then
    iptables -t nat -A "$PREROUTING" -i "$BRIDGE" -p tcp --dport 80 -j REDIRECT --to-ports 3129
    iptables -t nat -A "$PREROUTING" -i "$BRIDGE" -p tcp --dport 443 -j REDIRECT --to-ports 3130
    iptables -A "$INPUT" -i "$BRIDGE" -p tcp --dport 3129 -j ACCEPT
    iptables -A "$INPUT" -i "$BRIDGE" -p tcp --dport 3130 -j ACCEPT
    iptables -A "$INPUT" -i "$BRIDGE" -o dummy1 -j ACCEPT
    iptables -A "$FORWARD" -i "$BRIDGE" -o dummy1 -j ACCEPT
    # redirect registry traffic to registry that is on the localhost, if its in the /etc/hosts
#    if test -n "registry_ip"; then
#      iptables -t nat -A $PREROUTING -i "$BRIDGE" -p tcp -d $registry_ip --dport 5000 -j DNAT --to-destination 127.0.0.1:5000
#      iptables -A $INPUT -i "$BRIDGE" -p tcp --dport 5000 -j ACCEPT
#      iptables -A $FORWARD -i "$BRIDGE" -p tcp --dport 5000 -j ACCEPT
#    fi
fi
