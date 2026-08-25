# Working on Cluster Lab

This file is about working *on* this project. For what the tool does and how to run it, read
[README.md](README.md) — in particular [Repository Layout](README.md#repository-layout),
[Development](README.md#development) and [Gotchas](README.md#gotchas). Nothing here repeats
those; this covers the conventions the code follows but does not state.

Almost everything lives in one file: `bin/lab`, a ~2100-line bash script. Defaults are in
`config/defaults.sh`. Per-node and per-cluster provisioning are directories of shell
fragments under `node-setup/` and `seed-setup/`.

## Shell style in bin/lab

**Top-level function bodies are not indented.** Nested blocks use 2 spaces. Roughly 90 of
104 functions follow this; the remainder use a 2-space body. When editing an existing
function, match that function. When adding one, use a zero-indent body.

```bash
do_something() {
local target count
target="$(some_helper)"
if [ -n "$target" ]; then
  echo "working on $target"
fi
}
```

Indent with spaces, never tabs. (The single tab in the file is inside string data, not
indentation.)

A consequence worth knowing before you edit: because bodies sit at column 0, neither `^}`
nor `^name() {` is a reliable anchor. A `sed`/`awk` sweep over those patterns will also
match inside heredocs that contain shell snippets, of which there are several. Prefer
line-anchored edits or a unique surrounding string.

**Variables.** `local` for everything in new code. When the value comes from a command
substitution, declare the names bare first and assign after — it keeps the assignment's exit
status from being masked:

```bash
local saved prefix_file existing
prefix_file="$(network_prefix_file)"
```

`UPPER_CASE` is for config and derived globals (anything from `config/defaults.sh`,
`lab-env.sh`, or computed by `derive_network_values`). `lower_case` is for locals and
function names. Use `declare -gA` when a function must define a global map: `read_config`
sources `config/defaults.sh` from inside a function, so a plain `declare -A` there would
vanish on return.

**Errors.** There is no shared `die`/`err` helper — do not add one for a single call site.
The idiom is a message to stderr, then `return`:

```bash
echo "No ssh public key found" >&2
return 1
```

Validation failures add a second line telling the user what to do about it:

```bash
echo "LAB_PREFIX makes the libvirt bridge name too long: $bridge" >&2
echo "Shorten LAB_PREFIX or NET_NAME." >&2
return 1
```

## bin/lab is sourced by the tests — four invariants

`tests/network-prefix-allocation.sh` does `. bin/lab` and calls internal functions directly.
Four things must stay true or the suite breaks:

1. `set -euo pipefail` and the call to `dispatch_command` stay behind `if ! is_sourced`.
   Nothing else at the top level may have side effects beyond setting variables.
2. **Functions signal failure with `return`, never `exit`.** Every `exit` in the file is
   inside a subshell, a trap, an awk program, or a remote command string — keep it that way.
3. `read_config` is the only place that sources `config/defaults.sh` and `lab-env.sh`.
   Path-deriving functions read the `BASE_DIR` / `LAB_DIR` globals rather than recomputing
   from `BASH_SOURCE`, because tests override those globals.
4. **Any function a test can reach must read config variables defensively, as `${VAR:-}`.**
   The harness runs under `set -u` and never calls `read_config`, so a bare
   `$SOME_CONFIG_VAR` is an unbound-variable error that kills the entire run. This is not
   hypothetical: a bare `$PROXY_BUMP_CA_CRT` in `install_interceptor_network_hook` made one
   test fail silently for the life of the repo.
5. If root is required, print the command that should be executed, never do sudo in the script
   directly.

## Adding a lab command

Three places to edit, and one you usually should not:

1. **Define the function** at the top level, above `help()`.
2. **Add a `help()` entry.** It is a quoted heredoc, so nothing expands. Descriptions start
   at column 22; a name of 19 characters or more puts its description on the next line,
   indented to column 22. Multiword commands are written with dashes here (`sync-list`).
3. **Add the name to `VALID_COMMANDS`,** in underscore form. This array is only used for a
   membership test in `is_valid_command`, so its order is cosmetic — keep it roughly grouped
   like the help output, but do not reorder it to chase an exact match.
4. **`dispatch_command` usually needs no edit.** It maps dashes to underscores, so
   `lab sync-log` reaches `sync_log` with no alias registered anywhere. Touch it only if your
   command must work *outside* a lab directory — then add it to the `check|help)` arm, which
   is what skips `read_config` (and therefore skips requiring a `lab-env.sh`).

Two failure modes to recognise: a function with no array entry gives "Unknown command"; an
array entry with no function gives "Command not implemented".

## Setup-script contract

`node-setup/<name>/scripts.d/*.sh` run on every node; `seed-setup/<name>/scripts.d/*.sh` run
only on the single `seed`-role node. Both are executed by `run_scripts_on_nodes`.

- **No shebang, mode 644, not executable.** They are streamed to the node on stdin and run
  as `sudo bash`, so a shebang and exec bit would be meaningless.
- **Never read stdin** — it is already consumed by the script itself. Build inline data with
  a heredoc into a variable and pipe that instead.
- **No tty.** Use `DEBIAN_FRONTEND=noninteractive` and `apt-get -yq`.
- **Only `KUBE_VERSION` is passed in.** `SUDO_USER` is available via sudo. `NODES`,
  `NET_PREFIX`, `LAB_PREFIX`, `BASE_USER` and friends are *not*. If a script must also work
  standalone, default the version the way the existing ones do:
  `: "${KUBE_VERSION:=1.34.3}"`.
- **Execution order** is the shell glob, so lexicographic. Scripts run sequentially per node,
  and nodes run in parallel. The first non-zero exit aborts the remaining scripts on that
  node.
- **cwd is the ssh login home**, not `/`. Anything downloaded lands there.
- `seed-setup/calico` uses mixed-width numbering (`1-`, `2-`, `3-`, `40-`). A new `10-…`
  would sort *before* `2-init-control-plane.sh`. Pick a number that sorts where you mean.

**They run again on every `lab up`, so they must be idempotent.** Existing patterns to copy:

```bash
# marker check, in 50-containerd-install.sh
if command -v containerd > /dev/null; then
  echo "Skipping, containerd is present in image"
  exit 0
fi

# render to temp, compare, exit early if unchanged, in 51-containerd-setup.sh
if cmp --quiet $cfg $cfgNew; then
  exit 0
fi
mv $cfgNew $cfg
systemctl restart containerd
```

`2-init-control-plane.sh` and `40-git-server.sh` show the same idea for state that cannot be
probed with `command -v`: guard on the artifact the step produces
(`/etc/kubernetes/admin.conf`, an existing ssh key, a bare repo that already has a commit).
Prefer append-once over append: `grep -qxF "$line" "$file" || echo "$line" >> "$file"`.

Note `set -e` placement: `60-kube-tools-install.sh` deliberately puts its early-exit guard
*before* `set -e`.

`customize-image.sh` is optional. It runs once, inside the base image, under chroot — so
there is no systemd and no `systemctl`.

## Testing, and its hard limit

```bash
tests/network-prefix-allocation.sh      # from the repo root
```

Four cases, each printing `ok - <name>`; non-zero exit means failure. The harness sources
`bin/lab`, stubs `ip` and `virsh` into a temp dir placed first on `PATH`, and never touches
real libvirt.

To add a case: call `setup_case <name>` (which resets the config globals), write your stubs
into `$STUB_DIR`, assert with `assert_eq` / `assert_contains` / `fail`, and register it with
`run_test "<label>" test_<name>` at the bottom of the file. Redirect the function under test
into `"$CASE_DIR/out"` and `"$CASE_DIR/err"` so you can assert on messages; `on_exit` prints
those captures and keeps the temp dir when a run fails.

The stubs dispatch on the **exact whole argument string** (`case "$*" in "-o -4 addr show")`).
If you change the flags `bin/lab` passes to `ip` or `virsh`, a stub silently falls through
and the test sees empty output instead of failing cleanly. Re-run the suite after touching
network code.

Also run `bash -n` on every file you change. There is no CI, no `Makefile`, and `shellcheck`
is not installed here — do not claim a lint step that does not exist.

**`lab up` cannot be verified from an agent sandbox.** It needs sudo, the libvirt socket and
outbound network, none of which are available; `lab check` fails there with
`Failed to create socket: Operation not permitted`. So any change to node setup, cluster
bootstrap, or image building is desk-checked only. Say that plainly in your report rather
than implying it was tested. Verifying it for real means running `lab up` twice against live
KVM/libvirt on a throwaway lab directory.

## Never commit

`.gitignore` covers these; do not add them, and do not "clean them up" into a commit:

- `Downloads/` — cached base images, several GB.
- `*/.kubeconfig` — **cluster credentials.**
- `.network`, `.network.lock`, `.lab-sync/` — per-lab runtime state.
- `*~` — editor backups.

Running the tool mutates the working tree by design, including inside `examples/`. Those
artifacts are not uncommitted work.

## Git

Commit subjects are imperative, mostly lowercase, 3–7 words, with no `feat:`/`fix:` prefix,
no scope, and no body — that describes 100% of the history, so do not introduce Conventional
Commits. Work goes directly to `main`; there are no merge commits and no PR flow, so there
is no branch convention to follow.

**Do not commit or push unless asked.**

## Keep the docs in sync

`README.md` mirrors the command list, the configuration variables and the prerequisites. A
new command or config variable that is not reflected there will drift out of date. Follow-up
work goes in `TODO`, in its existing flat `- ` bullet style.
