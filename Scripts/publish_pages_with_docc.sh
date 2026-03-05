#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_DIR="${ROOT_DIR}/website"
OUT_DIR="${SITE_DIR}/out"
DOCC_CATALOG="${DOCC_CATALOG:-${ROOT_DIR}/Sources/TerraAutoInstrument/Terra.docc}"
TMP_DIR="${ROOT_DIR}/.tmp/pages-docc"
DOCC_OUT_DIR="${TMP_DIR}/docc"
PAGES_WORKTREE="${PAGES_WORKTREE:-/tmp/terra-gh-pages-publish}"

PAGES_BRANCH="gh-pages"
PUBLISH=1
BUILD_WEBSITE=1
BUILD_DOCC=1

usage() {
  cat <<'USAGE'
Usage: Scripts/publish_pages_with_docc.sh [options]

Builds website static output, generates DocC static docs, copies DocC into website/out/docc,
and optionally publishes everything to gh-pages.

Options:
  --no-publish         Build artifacts only; skip gh-pages publish
  --skip-website-build Skip `npm run build:pages`
  --skip-docc          Skip DocC generation/copy
  --pages-branch NAME  Pages branch (default: gh-pages)
  -h, --help           Show this help
USAGE
}

log() {
  printf '[pages+docc] %s\n' "$*"
}

require_cmd() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-publish)
      PUBLISH=0
      shift
      ;;
    --skip-website-build)
      BUILD_WEBSITE=0
      shift
      ;;
    --skip-docc)
      BUILD_DOCC=0
      shift
      ;;
    --pages-branch)
      PAGES_BRANCH="${2:-}"
      if [[ -z "$PAGES_BRANCH" ]]; then
        echo "--pages-branch requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_cmd git
require_cmd rsync
require_cmd swift
require_cmd xcrun

if [[ "$BUILD_WEBSITE" -eq 1 ]]; then
  require_cmd npm
fi

if [[ "$BUILD_DOCC" -eq 1 ]] && [[ ! -d "$DOCC_CATALOG" ]]; then
  echo "DocC catalog not found: $DOCC_CATALOG" >&2
  exit 1
fi

origin_url="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"
if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
  repo_slug="${GITHUB_REPOSITORY}"
elif [[ "$origin_url" =~ github\.com[:/]+([^/]+/[^/.]+)(\.git)?$ ]]; then
  repo_slug="${BASH_REMATCH[1]}"
else
  echo "Unable to determine GitHub repository slug. Set GITHUB_REPOSITORY=owner/repo." >&2
  exit 1
fi

repo_owner="${repo_slug%%/*}"
repo_name="${repo_slug##*/}"
hosting_base_path="${HOSTING_BASE_PATH:-${repo_name}/docc}"

mkdir -p "$TMP_DIR"

if [[ "$BUILD_WEBSITE" -eq 1 ]]; then
  log "Building website static export..."
  (
    cd "$SITE_DIR"
    npm run build:pages
  )
fi

if [[ "$BUILD_DOCC" -eq 1 ]]; then
  log "Generating symbol graphs for DocC..."
  symbolgraph_log="${TMP_DIR}/symbolgraph.log"
  if ! (
    cd "$ROOT_DIR"
    swift package dump-symbol-graph --skip-synthesized-members
  ) >"$symbolgraph_log" 2>&1; then
    if grep -q "Failed to emit symbol graph for 'TerraPackageTests'" "$symbolgraph_log"; then
      log "Proceeding despite TerraPackageTests symbol graph failure (non-DocC test target)."
    else
      cat "$symbolgraph_log" >&2
      exit 1
    fi
  fi

  symbolgraph_dir="$(find "$ROOT_DIR/.build" -type d -name symbolgraph | sort | tail -n 1)"
  if [[ -z "$symbolgraph_dir" ]]; then
    echo "Unable to locate symbolgraph directory under .build" >&2
    exit 1
  fi
  if [[ ! -f "$symbolgraph_dir/TerraCore.symbols.json" ]] || [[ ! -f "$symbolgraph_dir/Terra@TerraCore.symbols.json" ]]; then
    echo "Required Terra symbol graphs missing in $symbolgraph_dir" >&2
    cat "$symbolgraph_log" >&2
    exit 1
  fi

  log "Converting DocC catalog for static hosting..."
  rm -rf "$DOCC_OUT_DIR"
  mkdir -p "$DOCC_OUT_DIR"
  xcrun docc convert "$DOCC_CATALOG" \
    --additional-symbol-graph-dir "$symbolgraph_dir" \
    --output-path "$DOCC_OUT_DIR" \
    --transform-for-static-hosting \
    --hosting-base-path "$hosting_base_path" \
    --fallback-display-name "Terra" \
    --fallback-bundle-identifier "io.opentelemetry.terra" \
    --fallback-bundle-version "1.0.0"

  log "Copying DocC output into website export..."
  mkdir -p "$OUT_DIR/docc"
  rsync -a --delete "$DOCC_OUT_DIR/" "$OUT_DIR/docc/"
fi

if [[ "$PUBLISH" -eq 0 ]]; then
  log "Skipping publish (--no-publish)."
  log "Website output: $OUT_DIR"
  if [[ "$BUILD_DOCC" -eq 1 ]]; then
    log "DocC output copied to: $OUT_DIR/docc"
  fi
  exit 0
fi

log "Publishing to ${PAGES_BRANCH}..."
git -C "$ROOT_DIR" fetch origin "$PAGES_BRANCH"
git -C "$ROOT_DIR" worktree remove --force "$PAGES_WORKTREE" 2>/dev/null || true
git -C "$ROOT_DIR" worktree add --detach "$PAGES_WORKTREE" "origin/${PAGES_BRANCH}"

cleanup() {
  git -C "$ROOT_DIR" worktree remove --force "$PAGES_WORKTREE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

rsync -a --delete --exclude '.git' "$OUT_DIR/" "$PAGES_WORKTREE/"
touch "$PAGES_WORKTREE/.nojekyll"

current_head="$(git -C "$ROOT_DIR" rev-parse --short HEAD)"
(
  cd "$PAGES_WORKTREE"
  git add -A
  if git diff --cached --quiet; then
    log "No gh-pages changes detected."
  else
    git commit -m "Manual GitHub Pages publish (api-design ${current_head})"
    git push origin "HEAD:${PAGES_BRANCH}"
  fi
)

trap - EXIT
cleanup

site_url="https://${repo_owner}.github.io/${repo_name}/"
docc_url="${site_url}docc/documentation/terra/"
log "Publish complete."
log "Site URL: ${site_url}"
log "DocC URL: ${docc_url}"
