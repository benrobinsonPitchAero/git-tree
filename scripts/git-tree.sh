#!/usr/bin/env bash
# git-tree: generate a self-contained interactive HTML visualization of a repo's
# commit history. See SKILL.md. Pure bash extraction; D3 + data inlined offline.
set -euo pipefail

# ---- locate skill assets (script lives in <skill>/scripts/) ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE="$SKILL_DIR/assets/template.html"
D3FILE="$SKILL_DIR/assets/d3.v7.min.js"

# ---- defaults / flag parsing ----
DEPTH=150
BRANCH=""
NO_GITIGNORE=0
OUT="git-tree.html"

while [ $# -gt 0 ]; do
  case "$1" in
    --depth) DEPTH="${2:?--depth needs a number}"; shift 2 ;;
    --depth=*) DEPTH="${1#*=}"; shift ;;
    --branch) BRANCH="${2:?--branch needs a name}"; shift 2 ;;
    --branch=*) BRANCH="${1#*=}"; shift ;;
    --no-gitignore) NO_GITIGNORE=1; shift ;;
    --out) OUT="${2:?--out needs a path}"; shift 2 ;;
    -h|--help)
      echo "Usage: git-tree.sh [--depth N] [--branch <name>] [--no-gitignore]"; exit 0 ;;
    *) echo "git-tree: unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$DEPTH" in (*[!0-9]*|"") echo "git-tree: --depth must be a positive integer" >&2; exit 2 ;; esac

# ---- validate repo ----
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "git-tree: not inside a git repository. Nothing written." >&2
  exit 1
fi
if [ -z "$(git rev-list -n 1 --all 2>/dev/null)" ]; then
  echo "git-tree: this repository has no commits yet — nothing to visualize. Nothing written." >&2
  exit 1
fi
if [ ! -f "$TEMPLATE" ] || [ ! -f "$D3FILE" ]; then
  echo "git-tree: skill assets missing ($TEMPLATE / $D3FILE)." >&2
  exit 1
fi

# ---- choose base64 encoder (-w0 on GNU, plain on BSD/macOS) ----
b64() { if base64 --help 2>&1 | grep -q -- "-w"; then base64 -w0; else base64 | tr -d '\n'; fi; }

# ---- extract commit records ----
FMT='%H%x00%P%x00%an%x00%aI%x00%s%x00%b%x1e'
if [ -n "$BRANCH" ]; then
  if ! git rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null 2>&1 \
       && ! git rev-parse --verify --quiet "$BRANCH" >/dev/null 2>&1; then
    echo "git-tree: branch '$BRANCH' not found. Nothing written." >&2
    exit 1
  fi
  COMMITS_B64="$(git log "$BRANCH" --date-order -n "$DEPTH" --pretty=format:"$FMT" | b64)"
else
  COMMITS_B64="$(git log --all --date-order -n "$DEPTH" --pretty=format:"$FMT" | b64)"
fi

# ---- refs (branches, remotes, tags, HEAD marker) ----
# for-each-ref does NOT honor %x00/%x1e hex escapes, so use tab-separated fields and
# newline-delimited records (ref names cannot contain tabs or newlines).
REFS_FMT=$'%(refname)\t%(objectname)\t%(*objectname)\t%(HEAD)'
REFS_B64="$(git for-each-ref --format="$REFS_FMT" refs/heads refs/remotes refs/tags | b64)"

# ---- total commit count for truncation banner ----
if [ -n "$BRANCH" ]; then
  TOTAL="$(git rev-list --count "$BRANCH" 2>/dev/null || echo 0)"
else
  TOTAL="$(git rev-list --all --count 2>/dev/null || echo 0)"
fi

# JSON-safe branch value (may be empty)
if [ -n "$BRANCH" ]; then BRANCH_JSON="\"$(printf '%s' "$BRANCH" | sed 's/\\/\\\\/g; s/"/\\"/g')\""; else BRANCH_JSON="null"; fi

# ---- assemble the data <script> block ----
DATABLOCK="$(mktemp)"
trap 'rm -f "$DATABLOCK"' EXIT
{
  printf 'var RAW_COMMITS_B64 = "%s";\n' "$COMMITS_B64"
  printf 'var RAW_REFS_B64 = "%s";\n' "$REFS_B64"
  printf 'var META = { total: %s, depth: %s, branch: %s };\n' "${TOTAL:-0}" "$DEPTH" "$BRANCH_JSON"
} > "$DATABLOCK"

# ---- splice D3 + data into the template (awk avoids sed escaping pitfalls) ----
awk -v d3file="$D3FILE" -v datafile="$DATABLOCK" '
  /__D3_PLACEHOLDER__/   { while ((getline l < d3file)   > 0) print l; close(d3file);   next }
  /__DATA_PLACEHOLDER__/ { while ((getline l < datafile) > 0) print l; close(datafile); next }
  { print }
' "$TEMPLATE" > "$OUT"

echo "git-tree: wrote $OUT ($(wc -c < "$OUT" | tr -d ' ') bytes)"

# ---- .gitignore ----
if [ "$NO_GITIGNORE" -eq 0 ]; then
  GI=".gitignore"
  if [ -f "$GI" ] && grep -qxF "$OUT" "$GI" 2>/dev/null; then
    :
  else
    [ -f "$GI" ] && [ -n "$(tail -c1 "$GI" 2>/dev/null)" ] && printf '\n' >> "$GI"
    printf '%s\n' "$OUT" >> "$GI"
    echo "git-tree: added $OUT to $GI"
  fi
fi

# ---- auto-open in the default browser ----
open_cmd=""
case "$(uname -s)" in
  Linux*)  command -v xdg-open >/dev/null 2>&1 && open_cmd="xdg-open" ;;
  Darwin*) open_cmd="open" ;;
  MINGW*|MSYS*|CYGWIN*) open_cmd="start" ;;
esac
if [ -n "$open_cmd" ]; then
  ( "$open_cmd" "$OUT" >/dev/null 2>&1 & ) || true
  echo "git-tree: opening $OUT in your browser…"
else
  echo "git-tree: open $OUT manually in a browser."
fi
