#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORIGINAL_PATH="$PATH"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

. "$REPO_ROOT/bin/lab"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [ "$actual" != "$expected" ]; then
    fail "$label: expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  local needle="$1"
  local file="$2"
  local label="$3"
  if ! grep -F "$needle" "$file" >/dev/null; then
    fail "$label: expected '$needle' in $file"
  fi
}

setup_case() {
  local name="$1"
  CASE_DIR="$TMP_ROOT/$name"
  BASE_DIR="$CASE_DIR/base"
  LAB_DIR="$CASE_DIR/lab"
  STUB_DIR="$CASE_DIR/bin"
  STUB_STATE="$CASE_DIR/state"
  mkdir -p "$BASE_DIR" "$LAB_DIR" "$STUB_DIR" "$STUB_STATE"
  export STUB_STATE
  PATH="$STUB_DIR:$ORIGINAL_PATH"
  LAB_PREFIX=jens-single
  NET_NAME=lc
  NET_DOMAIN=k8s.local
  NET_PREFIX=
  NET_PREFIX_SOURCE=
  NET_PREFIX_POOL_BASE=192.168
  NET_PREFIX_POOL_START=120
  NET_PREFIX_POOL_END=125
}

write_used_host_ip_stub() {
  cat >"$STUB_DIR/ip" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "-o -4 addr show")
    cat <<'ADDRS'
3: virbr0    inet 192.168.122.1/24 brd 192.168.122.255 scope global virbr0\       valid_lft forever preferred_lft forever
6: single-lc    inet 192.168.121.1/24 brd 192.168.121.255 scope global single-lc\       valid_lft forever preferred_lft forever
8: cluster-lc    inet 192.168.120.1/24 brd 192.168.120.255 scope global cluster-lc\       valid_lft forever preferred_lft forever
ADDRS
    ;;
  "-4 route show") exit 0 ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$STUB_DIR/ip"
}

write_empty_virsh_stub() {
  cat >"$STUB_DIR/virsh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  net-list) exit 0 ;;
  net-info) exit 1 ;;
  net-define)
    touch "$STUB_STATE/defined"
    exit 0
    ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$STUB_DIR/virsh"
}

test_host_ipv4_addresses_are_reserved() {
  setup_case host-addresses
  write_used_host_ip_stub
  write_empty_virsh_stub

  assert_eq 192.168.123 "$(choose_network_prefix)" "host IPv4 prefixes"
}

test_configured_net_prefix_conflict_fails_before_define() {
  setup_case configured-conflict
  write_used_host_ip_stub
  write_empty_virsh_stub
  NET_PREFIX=192.168.121
  NET_PREFIX_SOURCE="using configured NET_PREFIX"
  derive_network_values

  if start_network >"$CASE_DIR/out" 2>"$CASE_DIR/err"; then
    fail "configured NET_PREFIX conflict unexpectedly succeeded"
  fi

  [ ! -f "$STUB_STATE/defined" ] || fail "virsh net-define was called for configured conflict"
  assert_contains "NET_PREFIX=192.168.121 is already in use" "$CASE_DIR/err" "configured conflict message"
  assert_contains "single-lc" "$CASE_DIR/err" "configured conflict owner"
}

test_network_file_conflict_fails_before_define() {
  setup_case network-file-conflict
  write_used_host_ip_stub
  write_empty_virsh_stub
  printf 'NET_PREFIX=192.168.121\n' >"$LAB_DIR/.network"

  resolve_network_config
  if start_network >"$CASE_DIR/out" 2>"$CASE_DIR/err"; then
    fail ".network NET_PREFIX conflict unexpectedly succeeded"
  fi

  [ ! -f "$STUB_STATE/defined" ] || fail "virsh net-define was called for .network conflict"
  assert_contains "Source: using previously assigned address from .network" "$CASE_DIR/err" ".network conflict source"
}

test_active_same_name_network_is_reused() {
  setup_case active-same-name
  cat >"$STUB_DIR/ip" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "-o -4 addr show")
    cat <<'ADDRS'
6: jens-single-lc    inet 192.168.121.1/24 brd 192.168.121.255 scope global jens-single-lc\       valid_lft forever preferred_lft forever
ADDRS
    ;;
  "-4 route show") exit 0 ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$STUB_DIR/ip"
  cat >"$STUB_DIR/virsh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  net-info)
    [ "$2" = jens-single-lc ] || exit 1
    cat <<'INFO'
Name:           jens-single-lc
Active:         yes
INFO
    ;;
  net-dumpxml)
    [ "$2" = jens-single-lc ] || exit 1
    cat <<'XML'
<network>
  <name>jens-single-lc</name>
  <forward mode='nat'/>
  <domain name='k8s.local'/>
  <bridge name='jens-single-lc' stp='on' delay='0'/>
  <ip address='192.168.121.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.121.100' end='192.168.121.254'/>
    </dhcp>
  </ip>
</network>
XML
    ;;
  net-autostart)
    touch "$STUB_STATE/autostart"
    ;;
  net-define|net-start)
    touch "$STUB_STATE/unexpected-$1"
    exit 1
    ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$STUB_DIR/virsh"

  resolve_network_config
  start_network >"$CASE_DIR/out" 2>"$CASE_DIR/err"

  assert_eq 192.168.121 "$NET_PREFIX" "active same-name prefix"
  [ -f "$STUB_STATE/autostart" ] || fail "active same-name network was not autostarted"
  [ ! -f "$STUB_STATE/unexpected-net-define" ] || fail "active same-name network was redefined"
  [ ! -f "$STUB_STATE/unexpected-net-start" ] || fail "active same-name network was restarted"
}

run_test() {
  local name="$1"
  shift
  "$@"
  echo "ok - $name"
}

run_test "host IPv4 addresses reserve prefixes" test_host_ipv4_addresses_are_reserved
run_test "configured NET_PREFIX conflict fails before define" test_configured_net_prefix_conflict_fails_before_define
run_test ".network conflict fails before define" test_network_file_conflict_fails_before_define
run_test "active same-name network is reused" test_active_same_name_network_is_reused
