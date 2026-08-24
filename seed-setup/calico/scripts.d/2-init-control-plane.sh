
# the normal init with a VIP / load balancer in front is:
# kubeadm init \
#  --apiserver-advertise-address=10.0.0.10 \
#  --control-plane-endpoint=k8s-control \
#  --pod-network-cidr=192.168.0.0/16

# Pod network
#
# IPs assigned to pods
# Parameter: --pod-network-cidr=10.244.0.0/16 
# default is --pod-network-cidr=192.168.0.0/16, however, 192.168.... is used for the KVM vms
#
# SVC / ClusterIP
#
# Default is: --service-cluster-ip-range=10.96.0.0/12
# Range: 10.96.0.0 - 10.111.255.255
#
# -apiserver-advertise-address="$apiserver_addr" can be omitted

# defaut is set in main script, however, make this work standalone as well
: "${KUBE_VERSION:=1.34.3}"

# this runs on every lab up, so skip the init if the cluster is already bootstrapped
if test -f /etc/kubernetes/admin.conf; then
  echo "Control plane already initialized, skipping kubeadm init"
else
  kubeadm init --kubernetes-version "v${KUBE_VERSION#v}" --pod-network-cidr=10.244.0.0/16
fi

kubeconfig_export="export KUBECONFIG=/etc/kubernetes/admin.conf"

# append only once, otherwise the line piles up on every run
add_kubeconfig_export() {
  local rc_file="$1"
  touch "$rc_file"
  grep -qxF "$kubeconfig_export" "$rc_file" || echo "$kubeconfig_export" >> "$rc_file"
}

add_kubeconfig_export /root/.bashrc
if test -n "$SUDO_USER"; then
  add_kubeconfig_export "/home/$SUDO_USER/.profile"
  chgrp sudo /etc/kubernetes/admin.conf
  chmod 660 /etc/kubernetes/admin.conf
fi
