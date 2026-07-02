# Cluster Lab Environment

Cluster Lab is lightweight orchestration for KVM virtual machines on top of
libvirt and `virsh`. It is intended for quickly creating disposable Kubernetes
lab clusters, roughly like Docker Compose for KVM-backed machines.

## Features

- Bash-based orchestration of KVM virtual machines.
- A default 4-node Kubernetes lab with one seed/control-plane node and three workers.
- Cached base images and downloads so rebuilds are fast after the first run.
- Automatic libvirt resource prefixes so multiple lab directories can run side by side.
- Optional continuous host-to-node directory sync.

## Limitations

- Linux hosts only.
- The default images and package setup target Ubuntu on `amd64`.
- Base image customization may need one-time root permission because it uses a
  loopback device and a chroot environment.

## Why Not Terraform or Vagrant?

This project uses `virsh` directly to keep the lab setup transparent and easy to
debug. Terraform and Vagrant can also manage local virtual machines, but they add
another abstraction layer on top of libvirt and were slower or harder to debug
for this use case.

## Prerequisites

- A Linux host with KVM support enabled.
- libvirt running and reachable through `qemu:///system`.
- Your user able to access libvirt, usually by being in the `libvirt` group.
- An SSH public key at `~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub`, or an
  explicit `SSH_PUBKEY`/`SSH_PUBKEY_PATH` in `lab-env.sh`.
- Host tools reported by `lab check`, including `virsh`, `virt-install`,
  `qemu-img`, `cloud-localds`, `ssh`, `rsync`, and `inotifywait`.

On Debian or Ubuntu, run `lab check` after installation. It prints the exact
`apt-get install` command for missing packages and warns if libvirt access is not
configured for the current user.

## Quick Start

Clone the repository and add the `lab` command to your shell path:

```bash
export CLUSTER_LAB_HOME=~/opt/cluster-lab
mkdir -p "$(dirname "$CLUSTER_LAB_HOME")"
git clone https://github.com/cruftex/kubernetes-lab.git "$CLUSTER_LAB_HOME"
export PATH="$CLUSTER_LAB_HOME/bin:$PATH"
```

Check host dependencies:

```bash
lab check
```

To test KVM and libvirt without creating a Kubernetes cluster, start the single
VM example:

```bash
cd
cp -a "$CLUSTER_LAB_HOME/examples/single" "$USER-single"
cd "$USER-single"
lab up
lab summary
lab tt box hostname
```

Create the default Kubernetes lab:

```bash
cd
cp -a "$CLUSTER_LAB_HOME/examples/cluster" "$USER-cluster"
cd "$USER-cluster"
lab up
KUBECONFIG=.kubeconfig kubectl get nodes
```

`lab up` creates or starts the VMs, runs node setup, bootstraps the cluster when
cluster roles are present, and writes a kubeconfig to `./.kubeconfig`.

## Common Commands

Except for `lab check`, run these commands from a lab directory that contains
`lab-env.sh`.

```bash
lab up                 # Create/start nodes and bootstrap the cluster when configured
lab start              # Start existing nodes and sync daemons
lab stop               # Stop sync daemons, then shut down nodes
lab purge              # Destroy all lab nodes and remove the lab network

lab summary            # Show node names and IPs
lab ips                # Print all node IPs
lab node-ip wk1        # Print one node IP
lab tt wk1 hostname    # Run a command on a node over SSH

lab fetch-kubeconfig   # Fetch ./.kubeconfig from the seed node
lab sync-list          # Show active sync daemons
lab sync-log -f        # Follow sync logs
lab help               # Show the full command list
```

Command names may be written with dashes. Internally, `lab` also accepts the
underscore form used by shell function names.

## Configuration

Each lab directory contains a `lab-env.sh` file. The most important settings are:

- `NODES`: associative array of node definitions. Each value is
  `<memory-mib> <vcpus> <role> [options]`.
- `NODE_SETUP`: node setup directory under `node-setup/`. The default is
  `apt-containerd`; set it to an empty value for a plain VM.
- `SEED_SETUP`: cluster bootstrap directory under `seed-setup/`.
- `LAB_PREFIX`: optional prefix for host-side libvirt resources.
- `NET_PREFIX`: optional fixed IPv4 `/24` prefix, for example `192.168.125`.
- `NET_PREFIX_POOL_BASE`, `NET_PREFIX_POOL_START`, `NET_PREFIX_POOL_END`:
  automatic network allocation pool.
- `SYNC_DIRS`: optional associative array of host-to-node sync mappings.

Example Kubernetes lab:

```bash
NODES=(
  [cp1]="4096 2 seed"
  [wk1]="3072 2 wk"
  [wk2]="3072 2 wk"
  [wk3]="3072 2 wk"
)
```

Example single VM with an explicit final IP octet:

```bash
NODE_SETUP=

NODES=(
  [box]="4096 2 none ip=65"
)
```

Supported roles are `seed`, `cp`, `wk`, and `none`. The default IP convention is
`cpN -> NET_PREFIX.(10 + N)` and `wkN -> NET_PREFIX.(20 + N)`. Use `ip=<octet>`
or `ip=<full-address>` in the node options to override that convention.

## Network Prefixes

To run multiple lab configs side by side, `lab` uses the lab directory name as
the default host-side prefix, similar to Docker Compose project names. You can
override it when needed:

```bash
lab up                 # in ./dev1, uses prefix dev1
LAB_PREFIX=dev2 lab up
lab --prefix dev3 up
# or put LAB_PREFIX=dev4 in that config's lab-env.sh
```

The prefix is applied to libvirt domains, node volumes, seed ISOs, and the
libvirt network. The default network suffix is `lc`, so a lab in `./dev1` uses
network `dev1-lc`. Node names inside this project and cloud-init hostnames stay
unchanged, for example `wk1` remains `wk1`.

If `NET_PREFIX` is not set in `lab-env.sh`, `lab` reuses the address from an
existing same-name libvirt network or from `.network` in the lab directory. If
neither exists, it allocates a free `/24` from `192.168.120.0/24` through
`192.168.199.0/24` and writes it to `.network`.

Run `lab purge` before deleting or editing `.network` to force a different
allocation. If a configured or saved prefix conflicts with a host network, `lab`
fails before defining the libvirt network and prints the conflicting owner.

## Directory Sync

`lab` can continuously sync one or more host directories into all nodes.

- Configure mappings in `lab-env.sh` via `SYNC_DIRS`.
- Source paths in `SYNC_DIRS` can be absolute or relative to the lab directory.
- Sync daemons start automatically on `lab up` and `lab start`.
- Sync daemons are stopped before node shutdown in `lab stop`.
- Use `lab sync-list` to show active synchronizations.
- Use `lab sync-log` or `lab sync-log -f` to view activity.
- Log lines include a UTC timestamp and sync runtime.
- Sync is event-driven via `inotifywait --monitor` and batches short event
  bursts before rsync.

> WARNING: Sync uses `rsync --delete`. The destination directory is continuously
> overwritten to match the source, and extra files at the destination are
> removed.

Example configuration:

```bash
declare -gA SYNC_DIRS=(
  ["./shared"]="/opt/lab/shared"
  ["/home/me/tools"]="/opt/lab/tools"
)
```

Useful commands:

```bash
lab sync-list
lab sync-log
lab sync-log -n 200
lab sync-log -f
```

Smoke test script:

```bash
# from repo root, test a specific lab directory
examples/sync-smoke-test.sh examples/cluster
```

## Registry Mirrors and Proxy Hooks

Kubernetes setup downloads images from `docker.io` and `registry.k8s.io`. The
default `apt-containerd` node setup checks for local mirrors and configures
containerd when one is reachable:

- `https://registry.internal:5000` as a `docker.io` mirror and
  `https://registry.internal:5001` as a `registry.k8s.io` mirror.
- `https://zotregistry.internal:5000` as a path-based Zot mirror.

If neither endpoint responds, setup continues without an image mirror and prints
`No image mirror detected`.

When `/etc/squid/ssl/ssl-bump-ca.crt` exists on the host, `lab` also installs
the libvirt network hook from `share/libvirt-network-hook.sh` and copies that CA
certificate into nodes so HTTPS interception can be trusted. If the certificate
is absent, this hook is skipped.

## Troubleshooting

- `lab check` reports missing commands or packages: install the suggested Debian
  packages and run `lab check` again.
- `Cannot connect to libvirt`: add your user to the `libvirt` group with
  `sudo usermod -aG libvirt "$USER"`, then log out and back in or run
  `newgrp libvirt`.
- `No ssh public key found`: create a key with `ssh-keygen` or set
  `SSH_PUBKEY`/`SSH_PUBKEY_PATH` in `lab-env.sh`.
- Network prefix conflict: choose another `NET_PREFIX`, unset it to allow
  automatic allocation, or run `lab purge` before forcing a new allocation.
- Existing libvirt network does not match this lab config: run `lab purge` for
  the lab, or remove the stale libvirt network after confirming it is unused.
- Need a fresh kubeconfig: run `lab fetch-kubeconfig` from the lab directory.

## Virsh Cheat Sheet

- Show running virtual machines: `virsh list`
- Show all virtual machines: `virsh list --all`
- Show libvirt networks: `virsh net-list --all`

## Kubectl Cheat Sheet

- All nodes: `KUBECONFIG=.kubeconfig kubectl get nodes -o wide`
- All pods: `KUBECONFIG=.kubeconfig kubectl get pods -A -o wide`
- All services and ports: `KUBECONFIG=.kubeconfig kubectl get svc -A`
