# Cluster Lab Environment

Cluster Lab is lightweight orchestration for KVM virtual machines on top of
libvirt and `virsh`. It is intended for quickly creating disposable Kubernetes
lab clusters, to test production grade configuration, roughly like 
Docker Compose for KVM-backed machines.

One command, `lab up`, turns an empty host into a running four-node `kubeadm`
cluster with a CNI, and `lab purge` removes it again.

- [Design Goals](#design-goals)
- [Repository Layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [What `lab up` Builds](#what-lab-up-builds)
- [Base Image Build and Caching](#base-image-build-and-caching)
- [Common Commands](#common-commands)
- [Configuration](#configuration)
- [Network Prefixes](#network-prefixes)
- [Directory Sync](#directory-sync)
- [Registry Mirrors and Proxy Hooks](#registry-mirrors-and-proxy-hooks)
- [Gotchas](#gotchas)
- [Why Not Kind, Minikube, Terraform or Vagrant?](#why-not-kind-minikube-terraform-or-vagrant)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)
- [Development](#development)
- [Virsh Cheat Sheet](#virsh-cheat-sheet)
- [Kubectl Cheat Sheet](#kubectl-cheat-sheet)
- [License](#license)

## Design Goals

- *Production typical:* Aimed at Kubernetes admins that want to test close to real hardware environments
- *Configuration as code:* A complete complex cluster can be bootstrapped with `lab up`
- *Reproducible:* The same configuration produces exactly the same cluster
- *Nearly no manual steps:* Almost everything is coded. `lab up` needs `sudo` for the base image and for the libvirt proxy hook, and add-on bootstraps like the Argo CD one in `examples/nautic` are run explicitly.
- *Fast:* Bootstrapping a cluster from scratch should only take a few minutes. Downloads can be cached via a registry or http proxy.
- *Simple and extensible:* Simple bash-based orchestration on top of virsh

For how this compares to other tools, see
[Why Not Kind, Minikube, Terraform or Vagrant?](#why-not-kind-minikube-terraform-or-vagrant).

## Repository Layout

```
bin/lab                  The entire tool. A single bash script, no installer.
config/defaults.sh       Every default value. The authoritative config reference.
lib/                     Helpers that need root, run via sudo from bin/lab.
node-setup/<name>/       Per-node provisioning. Selected by NODE_SETUP.
  customize-image.sh       Runs once inside the base image (chroot).
  scripts.d/*.sh           Run on every node over SSH, in glob order.
seed-setup/<name>/       Cluster bootstrap. Selected by SEED_SETUP.
  scripts.d/*.sh           Run on the seed node only, in glob order.
examples/                Ready-to-copy lab directories (see Quick Start).
share/                   Host-side extras: libvirt hooks, audit log analysis.
tests/                   Test scripts, run directly.
Downloads/               Cached base images. Created on first run, gitignored.
```

A *lab directory* is any directory containing a `lab-env.sh` file. You run `lab`
from inside it, and it holds that lab's state (`.network`, `.kubeconfig`,
`.lab-sync/`). Labs are independent and can run side by side; see
[Network Prefixes](#network-prefixes).

Shipped setups: `NODE_SETUP=apt-containerd` (Ubuntu + containerd + kube tools)
and `SEED_SETUP=calico` (kubeadm + Calico CNI). Adding your own is a matter of
dropping in a new directory; see [Development](#development).

## Prerequisites

- A Linux host with KVM support enabled.
- libvirt running and reachable through `qemu:///system`.
- Your user able to access libvirt, usually by being in the `libvirt` group.
- `bash` 4 or newer on the host.
- `python3` on the host. Every `lab up` needs it to multiplex setup script
  output from all nodes.
- An SSH public key at `~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub`, or an
  explicit `SSH_PUBKEY`/`SSH_PUBKEY_PATH` in `lab-env.sh`.
- Host tools reported by `lab check`, including `virsh`, `virt-install`,
  `qemu-img`, `cloud-localds`, `ssh`, `rsync`, and `inotifywait`.
- For base image customization: `qemu-nbd`, `growpart`, `partprobe`, `e2fsck`,
  `resize2fs`, `lsblk`, `udevadm`, and a loadable `nbd` kernel module.
- A few GB of free disk in the repository directory for the image cache in
  `Downloads/`, and the repository directory must be writable.
- Optional: `jq`, for the API server audit log helpers in `share/`.
- Outbound internet access from the nodes, unless you provide a
  [registry mirror or proxy](#registry-mirrors-and-proxy-hooks). Nodes fetch from
  `pkgs.k8s.io`, `download.docker.com`, `raw.githubusercontent.com` and
  `github.com`.

`lab` needs `sudo` in two places: customizing the base image (it uses `qemu-nbd`
and a chroot), and installing the libvirt network hook when an intercepting proxy
CA is present. Everything else runs as your user.

On Debian or Ubuntu, run `lab check` after installation. It prints the exact
`apt-get install` command for missing packages and warns if libvirt access is not
configured for the current user.

## Quick Start

Clone the repository and add the `lab` command to your shell path:

```bash
export CLUSTER_LAB_HOME=~/opt/cluster-lab
mkdir -p "$(dirname "$CLUSTER_LAB_HOME")"
git clone https://github.com/cruftex/cluster-lab.git "$CLUSTER_LAB_HOME"
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
cluster roles are present, and writes a kubeconfig to `./.kubeconfig`. The first
run also downloads and customizes the base image, which takes a while. Later runs
reuse it and are much faster.

### Examples

| Directory | What it is |
| --------- | ---------- |
| `examples/single` | One plain VM, no Kubernetes (`NODE_SETUP=`). Good for checking that KVM, libvirt and directory sync work. |
| `examples/cluster` | The default lab: one seed control plane plus three workers, with Calico. |
| `examples/nautic` | Same four nodes, plus a minimal Argo CD bootstrap. Further cluster setup is then driven by Argo CD. |

### The nautic example

`examples/nautic` deliberately keeps `lab up` minimal and hands the rest to
Argo CD. Two of its scripts are **not** run automatically:

```bash
cd
cp -a "$CLUSTER_LAB_HOME/examples/nautic" "$USER-nautic"
cd "$USER-nautic"
lab up

# host side: generate a self-signed wildcard cert for *.<labdir>.test
./10-ingress.sh

# node side: bootstrap/ is synced to /srv/bootstrap, but nothing runs it
lab tt cp1 'sudo bash /srv/bootstrap/20-argocd.sh'
```

`lab up` only rsyncs `./bootstrap` to `/srv/bootstrap` on the nodes (via
`SYNC_DIRS`). It never executes a lab directory's own scripts, so the Argo CD
install is an explicit manual step. `20-argocd.sh` installs Argo CD `v3.4.4` and
points it at the git server on the seed node.

## What `lab up` Builds

With the shipped defaults (`NODE_SETUP=apt-containerd`, `SEED_SETUP=calico`):

- **Topology:** the `NODES` map in `lab-env.sh`. The default is one seed control
  plane (`cp1`) and three workers (`wk1`–`wk3`) on Ubuntu 24.04 (noble), amd64.
- **Runtime:** containerd from Docker's apt repository, with `SystemdCgroup` on
  and `config_path=/etc/containerd/certs.d` for registry mirrors.
- **Kubernetes:** `kubeadm` at `KUBE_VERSION` (currently `1.34.3`), installed
  from `pkgs.k8s.io`. Workers are joined with a generated `kubeadm join` command.
- **CNI:** Calico `v3.31.3`.
- **Encryption:** WireGuard node-to-node encryption is **enabled** by default.
  `seed-setup/calico/scripts.d/3-install-calico-cni.sh` sets `wireguardEnabled`
  and `wireguardEnabledV6` on the default `FelixConfiguration`, because internal
  cluster traffic is otherwise unencrypted.
- **Cluster CIDRs:** pods `10.244.0.0/16`, services `10.96.0.0/12` (the kubeadm
  default). The pod CIDR deliberately avoids Calico's `192.168.0.0/16` default,
  because `192.168.x` is used for the VM network. These are separate from the
  libvirt network prefix described in [Network Prefixes](#network-prefixes).
- **A git server on the seed node.** `seed-setup/calico/scripts.d/40-git-server.sh`
  creates a `git` system user with `git-shell`, a bare repository at
  `/srv/git/cluster.git` with an initial commit, and an ed25519 key pair. It
  exists so Argo CD has a cluster-local configuration source. It currently runs
  for **every** lab using `SEED_SETUP=calico`, including `examples/cluster`,
  whether or not you use Argo CD.
- **A kubeconfig** copied to `./.kubeconfig` in the lab directory, mode 600.

Other behaviour worth knowing:

- Automatic libvirt resource prefixes, so multiple lab directories can run side
  by side. See [Network Prefixes](#network-prefixes).
- Optional continuous host-to-node directory sync. See
  [Directory Sync](#directory-sync).
- Node SSH host keys are added to your `~/.ssh/known_hosts`.

## Base Image Build and Caching

Bootstrapping is fast because packages are downloaded once, not once per node:

1. The Ubuntu cloud image is downloaded to `Downloads/` (`BASE_URL`/`BASE_VOL`).
2. If the selected node setup has a `customize-image.sh`, `lab` runs
   `lib/run-customize-image.sh` under `sudo`. That grows the image, attaches it
   with `qemu-nbd`, and chroots in to run the customizer. For `apt-containerd`
   this pre-installs `kubelet`, `kubeadm`, `kubectl` and `containerd.io`.
3. The result is uploaded as a libvirt volume, and each node gets a thin qcow2
   overlay on top of it.
4. On the nodes, `scripts.d` scripts detect the prebuilt image and skip their
   install steps.

So the first `lab up` is slow and every later one is quick, including after
`lab purge`. Note that `lab purge` does **not** discard the cached base image.
To force a rebuild, use `lab purge_base_volume`, or delete the `Downloads/`
artifacts.

## Common Commands

Except for `lab check`, run these commands from a lab directory that contains
`lab-env.sh`.

```bash
lab up                 # Create/start nodes and bootstrap the cluster when configured
lab start              # Start existing nodes and sync daemons
lab stop               # Stop sync daemons, then shut down nodes
lab purge              # Destroy all lab nodes and remove the lab network
lab purge-base-volume  # Also discard the cached base image, forcing a rebuild

lab status             # Node state, memory, disk and traffic in one table
lab status 5           # Same, reprinted every 5s with a CPU column, until Ctrl-C
lab summary            # Show node names and IPs
lab ips                # Print all node IPs
lab node-ip wk1        # Print one node IP
lab tt wk1 hostname    # Run a command on a node over SSH

lab fetch-kubeconfig   # Fetch ./.kubeconfig from the seed node
lab sync-list          # Show active sync daemons
lab sync-log -f        # Follow sync logs
lab help               # Show the full command list
```

`lab help` also lists the individual bootstrap steps (`up-nodes`, `up-cluster`,
`run-node-setup`, `run-seed-setup`, `join-workers`, and so on), which are useful
for re-running a single phase after a failure.

`lab status` reads everything from the host through libvirt, never over SSH, so it
still works for a node that has stopped answering. It shows each node's
`domstate --reason`, guest-reported free memory against the configured maximum, the
host disk the node's image actually occupies against its configured size, and
per-node traffic counters. Traffic is counted since the node booted and resets when
it restarts. Passing an interval adds a CPU column: libvirt only exposes a
cumulative CPU counter, so the percentage is measured across the gap between two
prints, normalised so 100% means every allocated vCPU is saturated.

Command names may be written with dashes. Internally, `lab` also accepts the
underscore form used by shell function names.

## Configuration

Each lab directory contains a `lab-env.sh` file that overrides the defaults in
`config/defaults.sh`. Read `config/defaults.sh` for the complete and
authoritative list; the settings below are the ones you are most likely to
change.

Topology and setup:

- `NODES`: associative array of node definitions. Each value is
  `<memory-mib> <vcpus> <role> [options]`.
- `NODE_SETUP`: node setup directory under `node-setup/`. The default is
  `apt-containerd`; set it to an empty value for a plain VM.
- `SEED_SETUP`: cluster bootstrap directory under `seed-setup/`. Default `calico`.
- `KUBE_VERSION`: Kubernetes version, default `1.34.3`. It selects both the
  `pkgs.k8s.io` repository and the `kubeadm init --kubernetes-version` argument.

Virtual machines:

- `DISK_G`: node disk size in GiB, default `20`.
- `BASE_URL`, `BASE_VOL`, `BASE_USER`: base cloud image URL, local filename and
  default login user. Default is the Ubuntu 24.04 noble amd64 cloud image.
- `OSVAR`: libvirt `--os-variant`, default `ubuntu24.04`.
- `POOL`: libvirt storage pool, default `default`.
- `MIN_FREE_DISK_G`: refuse to start nodes with less free disk than this, default
  `15`.
- `MAX_DISK_USAGE_PCT`: refuse to start nodes above this disk usage, default `90`.
  Set `MIN_FREE_DISK_G=0` and `MAX_DISK_USAGE_PCT=100` to disable the check.

`lab up` and `lab start` check both thresholds against the filesystems holding the
libvirt pool and the `Downloads/` image cache, and refuse to start anything if
either is exceeded. This is a guard against a confusing failure: when a disk fills
up, qemu pauses the guest with an I/O error, and because a paused VM does not answer
ARP, `ssh` reports `No route to host` as if the network were broken. See
[Troubleshooting](#troubleshooting).

Networking:

- `LAB_PREFIX`: optional prefix for host-side libvirt resources.
- `NET_PREFIX`: optional fixed network prefix, for example `192.168.125`. The lab
  network is always a `/24`, so this is its first three octets, not a CIDR.
- `NET_PREFIX_POOL_BASE`, `NET_PREFIX_POOL_START`, `NET_PREFIX_POOL_END`:
  automatic network allocation pool.
- `NET_NAME`: libvirt network name suffix, default `lc`.
- `NET_DOMAIN`: DNS domain for the nodes, default `k8s.local`.

Other:

- `SYNC_DIRS`: optional associative array of host-to-node sync mappings.
- `SSH_PUBKEY`, `SSH_PUBKEY_PATH`: SSH key to inject, if autodetection is wrong.
- `PROXY_BUMP_CA_CRT`: path to an intercepting proxy CA certificate on the host.

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

Supported roles are `seed`, `cp`, `wk`, and `none`.

Node names are not free-form: only the `cpN` and `wkN` patterns have an IP
convention, `cpN -> NET_PREFIX.(10 + N)` and `wkN -> NET_PREFIX.(20 + N)`. Any
other name **must** carry `ip=<octet>` or `ip=<full-address>` in its options, or
`lab` fails with `Assign an IP or name it cpN, wkN`. You can also use `ip=` to
override the convention for a `cpN`/`wkN` node.

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
neither exists, it allocates a free `/24` from `192.168.128.0` through
`192.168.191.0` and writes it to `.network`. That pool is
`NET_PREFIX_POOL_BASE.NET_PREFIX_POOL_START` to `…_END` in
`config/defaults.sh`, currently `192.168.128` to `192.168.191`.

Within a lab network, the gateway and DNS server is `NET_PREFIX.1` and the DHCP
range is `.100` to `.254`, though nodes themselves get static cloud-init
addresses. This is the VM network only; the in-cluster pod and service CIDRs are
listed under [What `lab up` Builds](#what-lab-up-builds).

Run `lab purge` before deleting or editing `.network` to force a different
allocation. If a configured or saved prefix conflicts with a host network, `lab`
fails before defining the libvirt network and prints the conflicting owner.
Allocation across lab directories is serialized with a `.network.lock` file in
the repository root.

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

## Registry Mirrors and Proxy Hooks

Kubernetes setup downloads container images from several public registries. The
`apt-containerd` node setup probes for a local mirror and, when one answers,
writes `/etc/containerd/certs.d/<registry>/hosts.toml` entries for it.

It probes `https://registry.internal:5001/v2/` first. If that answers, it
configures a per-registry port mapping:

| Mirror | Upstream registry |
| ------ | ----------------- |
| `https://registry.internal:5000` | `docker.io` |
| `https://registry.internal:5001` | `registry.k8s.io` |
| `https://registry.internal:5002` | `quay.io` |
| `https://registry.internal:5003` | `public.ecr.aws` |
| `https://registry.internal:5004` | `codeberg.org` |
| `https://registry.internal:5005` | `ghcr.io` |

Otherwise it probes `https://zotregistry.internal:5000/v2/` and, if that answers,
configures it as a single path-based Zot mirror for the same registry list.

If neither endpoint responds, setup continues without an image mirror and prints
`No image mirror detected`.

These hostnames and ports are hardcoded. There is no configuration variable for
them yet, so pointing the lab at your own mirror means editing
`node-setup/apt-containerd/scripts.d/51-containerd-setup.sh` and making the name
resolvable from the nodes.

When `/etc/squid/ssl/ssl-bump-ca.crt` exists on the host, `lab` also installs
the libvirt network hook from `share/libvirt-network-hook.sh` and copies that CA
certificate into nodes so HTTPS interception can be trusted. The hook redirects
bridge traffic on ports 80 and 443 to host ports 3129 and 3130, where it expects
a Squid instance. If the certificate is absent, this hook is skipped.

Setting up the mirror or the intercepting proxy itself is not yet documented; see
`TODO`.

## Gotchas

- **`lab purge` keeps the cached base image.** Use `lab purge-base-volume` to
  force a rebuild. See [Base Image Build and Caching](#base-image-build-and-caching).
- **Node names must be `cpN`/`wkN` or carry an explicit `ip=`.** See
  [Configuration](#configuration).
- **Disk usage.** `Downloads/` accumulates a few GB of base images per node
  setup, inside the repository directory.
- **The default guest password is `changeme`** for the cloud image user. Password
  SSH authentication is disabled (`ssh_pwauth: false`), so this only matters on
  the console, but do not expose these VMs beyond your host.
- **The libvirt storage pool is named `default`** and is created at
  `/var/lib/libvirt/images` if it does not exist.
- **Nodes need outbound internet access** unless a mirror or proxy is reachable.

## Why Not Kind, Minikube, Terraform or Vagrant?

**Kind and minikube** solve a different problem. They are great for testing
applications or services running on Kubernetes. With this project we can evaluate
and test the cluster setup itself as well, like networking, storage, and even
injecting faults at various levels.

**Terraform and Vagrant** can also manage local virtual machines, but they add
another abstraction layer on top of libvirt and were slower or harder to debug
for this use case. This project uses `virsh` directly to keep the lab setup
transparent and easy to debug.

## Limitations

- Linux hosts only.
- The default images and package setup target Ubuntu on `amd64`.
- Base image customization needs one-time root permission because it uses
  `qemu-nbd` and a chroot environment.
- Nodes are lab machines, not hardened ones. See the password note under
  [Gotchas](#gotchas).

## Troubleshooting

- `lab check` reports missing commands or packages: install the suggested Debian
  packages and run `lab check` again.
- `Cannot connect to libvirt`: add your user to the `libvirt` group with
  `sudo usermod -aG libvirt "$USER"`, then log out and back in or run
  `newgrp libvirt`.
- `No ssh public key found`: create a key with `ssh-keygen` or set
  `SSH_PUBKEY`/`SSH_PUBKEY_PATH` in `lab-env.sh`.
- `python3 is required for output mux`: install `python3` on the host.
- `Assign an IP or name it cpN, wkN`: rename the node or add `ip=<octet>` to its
  options in `NODES`.
- Network prefix conflict: choose another `NET_PREFIX`, unset it to allow
  automatic allocation, or run `lab purge` before forcing a new allocation.
- Existing libvirt network does not match this lab config: run `lab purge` for
  the lab, or remove the stale libvirt network after confirming it is unused.
- Need a fresh kubeconfig: run `lab fetch-kubeconfig` from the lab directory.
- Suspect a bad base image: run `lab purge-base-volume`, then `lab up` again.
- `Not enough disk space on …`: free space, or lower `MIN_FREE_DISK_G` /
  raise `MAX_DISK_USAGE_PCT`. `lab purge` reclaims the node disks, and stale
  images in `Downloads/` for setups you no longer use can be deleted.
- `ssh: connect to host … No route to host` on a node that `lab up` just
  reported as fine: run `lab status`, which shows each node's state directly. A guest
  shown as `paused (I/O error)` ran out of disk — qemu pauses it on `ENOSPC`,
  and a paused VM does not answer ARP, so `ssh` fails as if the network were
  down. Free space, then `lab purge` and `lab up`; the guest filesystem may
  have seen write errors, so a rebuild is safer than resuming.

## Development

Run the tests directly from the repository root:

```bash
tests/network-prefix-allocation.sh
```

Each test prints `ok - <name>`. The test harness sources `bin/lab` and stubs `ip`
and `virsh` on `PATH`, so it does not touch real libvirt state.

### Adding a node setup

Create `node-setup/<name>/` and set `NODE_SETUP=<name>` in `lab-env.sh`.

- `scripts.d/*.sh` run on every node over SSH with `sudo bash`, in glob order,
  with `KUBE_VERSION` exported. Number them like the existing ones.
- An optional `customize-image.sh` runs once inside the base image in a chroot,
  for anything you want baked in rather than installed per node.
- Make scripts idempotent. They run again on every `lab up`, so guard installs
  with a `command -v` check the way `50-containerd-install.sh` does.

### Adding a cluster bootstrap

Create `seed-setup/<name>/scripts.d/` and set `SEED_SETUP=<name>`. These run only
on the node with role `seed`. Look at `seed-setup/calico/` for the sequence:
pull images, `kubeadm init`, install a CNI.

### Extras in share/

```bash
share/apiserver-audit-top-urls.sh [log|-] [TOP] [DEPTH]      # top request paths
share/apiserver-audit-top-urls-rps.sh [log|-] [TOP] [DEPTH]  # same, as requests/sec
```

Both read a Kubernetes API server audit log and need `jq`.

## Virsh Cheat Sheet

- Show running virtual machines: `virsh list`
- Show all virtual machines: `virsh list --all`
- Show libvirt networks: `virsh net-list --all`

## Kubectl Cheat Sheet

- All nodes: `KUBECONFIG=.kubeconfig kubectl get nodes -o wide`
- All pods: `KUBECONFIG=.kubeconfig kubectl get pods -A -o wide`
- All services and ports: `KUBECONFIG=.kubeconfig kubectl get svc -A`

## License

Copyright 2026 Jens Wilke.

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
