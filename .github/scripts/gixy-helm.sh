#!/usr/bin/env bash
#
# gixy-helm.sh — run Gixy (https://gixy.io) against the NGINX config a Helm chart renders.
#
# Gixy needs real nginx config files, but our charts ship them as ConfigMaps.
# This script:
#   1. renders the chart (helm template) — or reads an already-rendered manifest,
#   2. pulls the listed keys out of the ConfigMaps,
#   3. lays them out in a temp dir at the same paths they get mounted at in the pod,
#      rewriting absolute `include /...;` paths so Gixy can follow them,
#   4. prints the full Gixy report and fails if anything at/above --fail-on is found.
#
# Usage:
#   gixy-helm.sh --chart charts/foo -f values.yaml [-f more.yaml] [--set k=v] \
#                --map nginx.conf=/etc/nginx/nginx.conf \
#                --map server.conf=/etc/nginx/default.d/server.conf \
#                [--optional-map redirections.conf=/etc/nginx/conf.d/redirections.conf] \
#                [--fail-on high|medium|low|any] [--name label] [-- extra gixy args]
#
#   --rendered FILE   use an existing multi-doc manifest instead of running helm
#   --entry PATH      container path of the main nginx.conf (default /etc/nginx/nginx.conf)
#   --fail-on LEVEL   severity that fails the job (default: high). Full report is always printed.
#
set -euo pipefail

CHART=""; RENDERED=""; NAME="gixy-check"; ENTRY="/etc/nginx/nginx.conf"; FAIL_ON="high"
VALUES=(); HELM_EXTRA=(); MAPS=(); OPT_MAPS=(); GIXY_EXTRA=()

die() { echo "::error::$*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--chart)         CHART="$2"; shift 2 ;;
    -f|--values)        VALUES+=(-f "$2"); shift 2 ;;
    --set)              HELM_EXTRA+=(--set "$2"); shift 2 ;;
    -m|--map)           MAPS+=("$2"); shift 2 ;;
    -o|--optional-map)  OPT_MAPS+=("$2"); shift 2 ;;
    --entry)            ENTRY="$2"; shift 2 ;;
    --fail-on)          FAIL_ON="$2"; shift 2 ;;
    --name)             NAME="$2"; shift 2 ;;
    --rendered)         RENDERED="$2"; shift 2 ;;
    --)                 shift; GIXY_EXTRA=("$@"); break ;;
    -h|--help)          sed -n '2,25p' "$0"; exit 0 ;;
    *)                  die "unknown argument: $1" ;;
  esac
done

[[ ${#MAPS[@]} -gt 0 ]] || die "at least one --map key=/container/path is required"
command -v gixy >/dev/null || die "gixy not found (pip install gixy-next)"
command -v yq   >/dev/null || die "yq (mikefarah) not found"

case "$FAIL_ON" in
  high)   LEVEL="-lll" ;;
  medium) LEVEL="-ll"  ;;
  low)    LEVEL="-l"   ;;
  any)    LEVEL=""     ;;
  *)      die "--fail-on must be high|medium|low|any" ;;
esac

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
ROOT="$WORK/root"; mkdir -p "$ROOT"

# 1. Render ---------------------------------------------------------------
if [[ -z "$RENDERED" ]]; then
  [[ -n "$CHART" ]] || die "--chart (or --rendered) is required"
  RENDERED="$WORK/rendered.yaml"
  helm template "$NAME" "$CHART" "${VALUES[@]}" "${HELM_EXTRA[@]}" \
    > "$RENDERED" 2>"$WORK/helm.err" \
    || { cat "$WORK/helm.err" >&2; die "helm template failed for $NAME"; }
fi

# 2 + 3. Extract ConfigMap keys to their in-pod paths ----------------------
extract() {  # $1=key  $2=container path  $3=required|optional
  local key="$1" dest="$ROOT$2" mode="$3"
  local content
  content="$(yq eval "select(.kind == \"ConfigMap\") | .data[\"$key\"] | select(. != null)" "$RENDERED")"
  if [[ -z "$content" ]]; then
    [[ "$mode" == "optional" ]] && { echo "  (skip) $key not rendered for $NAME"; return 0; }
    die "[$NAME] ConfigMap key '$key' not found in rendered chart"
  fi
  # Template leftovers make Gixy silently stop parsing — catch them here.
  if grep -nE '<no value>|\{\{|\}\}' <<<"$content" >&2; then
    die "[$NAME] '$key' contains unrendered template markers (lines above)"
  fi
  mkdir -p "$(dirname "$dest")"
  printf '%s\n' "$content" > "$dest"
  echo "  $key -> $2"
}

echo "== [$NAME] building nginx config tree"
for m in "${MAPS[@]}";     do extract "${m%%=*}" "${m#*=}" required; done
for m in "${OPT_MAPS[@]:-}"; do [[ -n "$m" ]] && extract "${m%%=*}" "${m#*=}" optional; done

# Files that exist in the image but not in the chart. Empty placeholder is enough for Gixy.
mkdir -p "$ROOT/etc/nginx"; touch "$ROOT/etc/nginx/mime.types"

# Point every absolute include at the temp tree.
while IFS= read -r -d '' f; do
  sed -i -E "s#^([[:space:]]*include[[:space:]]+)/#\1$ROOT/#" "$f"
done < <(find "$ROOT" -type f -print0)

MAIN="$ROOT$ENTRY"
[[ -f "$MAIN" ]] || die "entry config $ENTRY was not produced by the --map list"

# 4. Run Gixy ----------------------------------------------------------------
echo "== [$NAME] gixy report (fail-on: $FAIL_ON)"
set +e
gixy "${GIXY_EXTRA[@]}" -f text "$MAIN" >"$WORK/report.txt" 2>"$WORK/stderr.txt"
gixy "${GIXY_EXTRA[@]}" $LEVEL -f text "$MAIN" >/dev/null 2>&1
GATE=$?
set -e

# Show paths relative to the pod, not the temp dir
sed "s#$ROOT##g" "$WORK/report.txt"
sed "s#$ROOT##g" "$WORK/stderr.txt" >&2

# Gixy is a linter, not a validator: if it could not parse something, don't trust a green result.
if grep -q "could not fully analyze" "$WORK/stderr.txt"; then
  die "[$NAME] gixy could not fully parse the config (see above). Run nginx -t / fix the template."
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  REPORT="$(sed "s#$ROOT##g" "$WORK/report.txt")"
  COUNTS="$(grep -E '^[[:space:]]+(Informational|Low|Medium|High):' <<<"$REPORT" \
    | sed -E 's/^[[:space:]]+([A-Za-z]+): ([0-9]+)/\2 \1/' | paste -sd'|' - | sed 's/|/ · /g' || true)"
  if [[ $GATE -eq 0 ]]; then
    BADGE="✅"; STATUS_LINE="**Passed**"
  else
    BADGE="❌"; STATUS_LINE="**Failed** — severity \`$FAIL_ON\` or higher found"
  fi
  {
    echo "### $BADGE gixy — $NAME"
    echo ""
    echo "$STATUS_LINE  ·  fail-on: \`$FAIL_ON\`"
    echo ""
    echo "$COUNTS"
    echo ""
    echo "<details><summary>Full report</summary>"
    echo ""
    echo '```text'
    echo "$REPORT"
    echo '```'
    echo "</details>"
    echo ""
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [[ $GATE -ne 0 ]]; then
  die "[$NAME] gixy found issues at severity '$FAIL_ON' or higher"
fi
echo "== [$NAME] gixy: no findings at '$FAIL_ON' or higher"