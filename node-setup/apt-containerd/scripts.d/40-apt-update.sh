
set -e

# stop system jobs that do apt stuff
# also make sure that cloud init does not have package update enabled
systemctl stop apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
systemctl stop unattended-upgrades.service 2>/dev/null || true
systemctl kill --kill-who=all apt-daily.service apt-daily-upgrade.service 2>/dev/null || true

# if joe is present, assume the base image was prebuild
if command -v joe > /dev/null; then
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get upgrade -y
apt-get install -yq joe
