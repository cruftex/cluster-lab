#!/usr/bin/env bash

# mount image and run customization script in chroot environment
# requires root permissions

# Remark:
# virt-customize did not work, so we mount all relevant things into a
# chroot environment

set -euo pipefail

set -x

source_image="$1"
img="$2"
customizer="$3"

# the space for the additional packages may not be sufficient
# grow the partition
additional_g=10

cp -a "$source_image" "$img"
qemu-img resize "$img" +${additional_g}G
chown $SUDO_USER:$SUDO_USER "$img"

modprobe nbd

dev=""
for d in /sys/class/block/nbd[0-9]; do
  [ -e "$d" ] || continue
  cand=$(basename "$d")
  if [ ! -e "$d/pid" ]; then
    dev="$cand"
    break
  fi
done

if [ -z "$dev" ]; then
  echo "No free /dev/nbdN device found" >&2
  exit 1
fi

wait_for_partition() {
  for i in {1..50}; do
    lsblk -n "$1" | grep -q part && return 0
    sleep 0.1
  done
  echo "Timed out waiting for partition device $part" >&2
  return 1
}

mnt=$(mktemp -d)

cleanup() {
  df -h $mnt
  (
    cd $mnt
    # this is dangerous, do it better in chroot!
    rm -f customizer.sh
    rm -f etc/resolv.conf
    if test -d etc; then
      ln -s ../run/systemd/resolve/stub-resolv.conf etc/resolv.conf
    fi
  )
  umount $mnt/dev $mnt/proc $mnt/sys 2>/dev/null || true
  umount $mnt 2>/dev/null || true
  qemu-nbd --disconnect /dev/$dev || true
  rm -rf $mnt
}

trap cleanup EXIT

qemu-nbd --connect=/dev/$dev "$img"
growpart /dev/$dev 1

# make sure devices for partions are available
partprobe /dev/$dev
udevadm settle || true
part=/dev/${dev}p1
wait_for_partition "$part"

e2fsck -f "$part"
resize2fs "$part"

mkdir -p "$mnt"

mount "$part" "$mnt"
mount --bind /dev $mnt/dev
mount --bind /proc $mnt/proc
mount --bind /sys $mnt/sys

df -h $mnt

cp -a $customizer $mnt/customizer.sh
(
  cd $mnt
  rm -f etc/resolv.conf
  echo "nameserver 1.1.1.1" > etc/resolv.conf
)

chroot $mnt bash /customizer.sh

# unmount done in cleanup
exit 0;
