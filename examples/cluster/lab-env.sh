
NODES=(
  [cp1]="4096 2 seed"
  [wk1]="3072 2 wk"
  [wk2]="3072 2 wk"
  [wk3]="3072 2 wk"
)

# Optional host->node sync mappings (src => dst).
# Source can be absolute or relative to this lab directory.
# Destination must be absolute on the nodes.
# declare -gA SYNC_DIRS=(
#   ["./shared"]="/opt/lab/shared"
# )
