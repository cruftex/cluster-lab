# Local git server to be used by Argo CD
# TODO: move that to nautic

set -e

adduser --system --shell /usr/bin/git-shell --group --home /srv/git git

mkdir -p /srv/git/cluster.git
git init --bare -b main /srv/git/cluster.git
mkdir -p /srv/git/.ssh
cat /home/$SUDO_USER/.ssh/authorized_keys > /srv/git/.ssh/authorized_keys
ssh-keygen -t ed25519 -N "" -f /srv/git/.ssh/id_ed25519
cat /srv/git/.ssh/id_ed25519.pub >> /srv/git/.ssh/authorized_keys
chown -R git:git /srv/git
chmod 700 /srv/git/.ssh
chmod 600 /srv/git/.ssh/authorized_keys

#
# Put one seed file, otherwise ArgoCD connection will fail since nothing is there
# 
git config --global user.email "cp1@cluster-lab.test"
git config --global user.name "40-git-server.sh setup script"

tmpdir="$(mktemp -d)"
ssh-keyscan localhost >> /root/.ssh/known_hosts
export GIT_SSH_COMMAND="ssh -i /srv/git/.ssh/id_ed25519"
git clone git@localhost:cluster.git "$tmpdir"
cd "$tmpdir"
git switch -c main
cat > "README.md" <<'EOF'
cluster configuration repository
EOF
git add README.md
git commit -m "Initial commit"
git push origin main
cd /
rm -rf "$tmpdir"

echo git initialized
