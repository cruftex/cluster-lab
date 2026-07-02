#!/usr/bin/env bash
set -euo pipefail

INPUT="${1:-/dev/stdin}"
TOP="${2:-10}"
DEPTH="${3:-4}"   # max path segments after leading "/"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required. Install with: sudo apt-get install -y jq" >&2
  exit 1
fi

TMP=$(mktemp)

# Emit: "<timestamp> <collapsed-prefix>"
# We also sort by timestamp so START/END are accurate even if log interleaves.
jq -r '
  select(.requestURI? and .requestReceivedTimestamp?)
  | .requestReceivedTimestamp + " " + (.requestURI | split("?")[0])
' "$INPUT" \
| awk -v depth="$DEPTH" '
  NF>=2 {
    ts=$1
    path=$2

    # split path by "/", keep "/" + first N non-empty segments
    n = split(path, a, "/")
    out = "/"
    kept = 0
    for (i=2; i<=n && kept<depth; i++) {
      if (a[i] == "") continue
      out = out a[i] "/"
      kept++
    }
    if (out != "/" && substr(out, length(out), 1) == "/") out = substr(out, 1, length(out)-1)

    print ts, out
  }
' \
| sort > "$TMP"

if [[ ! -s "$TMP" ]]; then
  echo "No valid audit entries found."
  rm -f "$TMP"
  exit 0
fi

START_TS=$(head -n1 "$TMP" | awk '{print $1}')
END_TS=$(tail -n1 "$TMP" | awk '{print $1}')

START_EPOCH=$(date -d "$START_TS" +%s)
END_EPOCH=$(date -d "$END_TS" +%s)

DURATION=$((END_EPOCH - START_EPOCH))
if [[ "$DURATION" -le 0 ]]; then
  DURATION=1
fi

echo "Log timespan: $DURATION seconds"
echo

# Count prefixes (field 2), aggregate, compute rps
awk '{print $2}' "$TMP" \
| sort \
| uniq -c \
| sort -nr \
| head -n "$TOP" \
| awk -v dur="$DURATION" '
{
  count=$1
  prefix=$2
  rps=count/dur
  printf "%8d  %8.3f rps  %s\n", count, rps, prefix
}
'

rm -f "$TMP"
