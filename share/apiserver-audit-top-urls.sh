#!/usr/bin/env bash
set -euo pipefail

LOG="${1:-/dev/stdin}"
TOP="${2:-10}"
DEPTH="${3:-4}"   # number of path segments to keep (after leading slash)

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required. Install with: sudo apt-get install -y jq" >&2
  exit 1
fi

jq -r '
  select(.requestURI? != null)
  | .requestURI
  | split("?")[0]
' \
| awk -v depth="$DEPTH" '
  NF {
    # split path on "/", keep leading "/" plus first N segments
    n = split($0, a, "/")
    out = "/"
    kept = 0
    for (i=2; i<=n && kept<depth; i++) {
      if (a[i] == "") continue
      out = out a[i] "/"
      kept++
    }
    # remove trailing slash unless it is just "/"
    if (out != "/" && substr(out, length(out), 1) == "/") out = substr(out, 1, length(out)-1)
    print out
  }
' \
| sort \
| uniq -c \
| sort -nr \
| head -n "$TOP" \
| awk '{printf "%8s  %s\n",$1,$2}'
