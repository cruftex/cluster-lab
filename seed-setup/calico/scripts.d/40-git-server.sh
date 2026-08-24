# Local git server to be used by Argo CD
# TODO: move that to nautic

set -e

# This script runs on every lab up, so every step has to be re-runnable.

if id git >/dev/null 2>&1; then
  echo "user git already present"
else
  adduser --system --shell /usr/bin/git-shell --group --home /srv/git git
fi

mkdir -p /srv/git/cluster.git
if test -f /srv/git/cluster.git/HEAD; then
  echo "bare repository already present"
else
  git init --bare -b main /srv/git/cluster.git
fi

mkdir -p /srv/git/.ssh
if test -f /srv/git/.ssh/id_ed25519; then
  echo "git server key already present"
else
  ssh-keygen -t ed25519 -N "" -f /srv/git/.ssh/id_ed25519
fi

# rebuilt from scratch each run, so the key list cannot accumulate duplicates
cat "/home/$SUDO_USER/.ssh/authorized_keys" > /srv/git/.ssh/authorized_keys
cat /srv/git/.ssh/id_ed25519.pub >> /srv/git/.ssh/authorized_keys
chown -R git:git /srv/git
chmod 700 /srv/git/.ssh
chmod 600 /srv/git/.ssh/authorized_keys

#
# Put one seed file, otherwise ArgoCD connection will fail since nothing is there
#
if git --git-dir=/srv/git/cluster.git rev-parse --quiet --verify HEAD >/dev/null; then
  echo "seed commit already present"
else
  git config --global user.email "cp1@cluster-lab.test"
  git config --global user.name "40-git-server.sh setup script"

  # replace the host key instead of appending, otherwise known_hosts grows on every run
  mkdir -p /root/.ssh
  touch /root/.ssh/known_hosts
  ssh-keygen -R localhost -f /root/.ssh/known_hosts >/dev/null 2>&1 || true
  ssh-keyscan localhost >> /root/.ssh/known_hosts 2>/dev/null

  tmpdir="$(mktemp -d)"
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
fi

echo git initialized
