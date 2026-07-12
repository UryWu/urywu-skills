#!/bin/bash
# scripts/bump_version.sh — bump backend / frontend versions
#
# Each component has its own version slot. By default both move together.
# Pass --backend / --frontend to override individual components
# (e.g. hotfix a single one while the others advance normally).
#
# Usage:
#   ./scripts/bump_version.sh 1.2.0                         # all → 1.2.0
#   ./scripts/bump_version.sh 1.2.0 --backend 1.1.5         # backend 1.1.5, others 1.2.0
#   ./scripts/bump_version.sh patch                         # all += patch (each from own current)
#   ./scripts/bump_version.sh patch --frontend minor        # backend += patch, frontend += minor
#
# After running, do `git diff` then commit/tag/push manually:
#   git add -A && git commit -m "..."
#   git tag -a v1.2.0 -m "..."
#   git push origin main && git push origin v1.2.0
#
# Where each component's current version is read from:
#   backend   ← backend/pyproject.toml        (Python source of truth)
#   frontend  ← frontend/package.json         (npm source of truth)
#   (lockfile regen: see sync_lock_backend / sync_lock_frontend)
#
# Note: lockfiles (uv.lock / package-lock.json) are intentionally NOT in the
# patch list. A blind sed would corrupt transitive dep versions whose own version
# happens to match ours (e.g. bump 1.1.1 → 1.2.0 would turn pathspec 1.1.1 into a
# nonexistent 1.2.0). Instead, we let the package manager regenerate the lock
# from the updated source-of-truth: `uv lock` reads pyproject.toml, `npm install`
# reads package.json — both only bump the openlink entry and leave transitive
# versions untouched.
#
# Note: commit / tag / push are intentionally NOT in this script — they need
# contextual messages and are kept under manual control.
#
# ---------------------------------------------------------------
# TEMPLATE NOTE (shipped with the `fastapi-vue-version-bump` skill):
# Pre-configured for **2 components** — `backend` (Python/FastAPI · `uv lock`)
#   and `frontend` (Vue 3 · `npm install`). Default source-of-truth files
#   match each toolchain's convention (pyproject.toml / package.json).
# To add a third component, append entries to the COMPONENT_FILES /
#   COMPONENT_READ / COMPONENT_SYNC arrays and a `sync_lock_<name>` function.
# To swap toolchains, edit `sync_lock_backend` / `sync_lock_frontend`.
# ---------------------------------------------------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ── Parse arguments ──────────────────────────────────────────────────────

SPEC=""
OVERRIDE_BACKEND=""
OVERRIDE_FRONTEND=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend)   OVERRIDE_BACKEND="$2";   shift 2 ;;
    --frontend)  OVERRIDE_FRONTEND="$2";  shift 2 ;;
    -h|--help)
      sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      if [[ -n "$SPEC" ]]; then
        log_error "unexpected positional argument: $1 (only one of X.Y.Z | patch | minor | major allowed)"
        exit 1
      fi
      SPEC="$1"
      shift
      ;;
  esac
done

if [[ -z "$SPEC" ]]; then
  log_error "missing version spec: pass X.Y.Z or patch|minor|major"
  exit 1
fi

# ── Component definitions ────────────────────────────────────────────────
# Each component has:
#   - name (display + flag prefix)
#   - files: list of "path|sed-mode" entries (mode: json wraps in quotes)
#   - read_version: command that prints current version to stdout
#   - sync_lock: command that re-syncs the lockfile (run after edits)

read_version_backend() {
  grep -E '^version = "' backend/pyproject.toml | head -1 | sed -E 's/^version = "(.+)"$/\1/'
}
read_version_frontend() {
  grep -E '"version":' frontend/package.json | head -1 | sed -E 's/.*"version": *"([^"]+)".*/\1/'
}

sync_lock_backend()   { (cd backend   && uv lock            >/dev/null 2>&1); }
sync_lock_frontend()  { (cd frontend  && npm install --silent --no-audit --no-fund >/dev/null 2>&1); }

declare -A COMPONENT_FILES=(
  [backend]="backend/pyproject.toml|toml
backend/VERSION|plain
backend/app/main.py|python
backend/app/schemas/types.py|python
backend/app/api/endpoints/health.py|python"
  [frontend]="frontend/package.json|json"
)
declare -A COMPONENT_READ=(
  [backend]=read_version_backend
  [frontend]=read_version_frontend
)
declare -A COMPONENT_SYNC=(
  [backend]=sync_lock_backend
  [frontend]=sync_lock_frontend
)

# ── Resolve target version per component ────────────────────────────────

bump_kind() {
  # $1: kind (patch|minor|major), $2: current (X.Y.Z) → echoes new
  local kind="$1" cur="$2"
  IFS='.' read -r MAJOR MINOR PATCH <<< "$cur"
  case "$kind" in
    patch) echo "$MAJOR.$MINOR.$((PATCH + 1))" ;;
    minor) echo "$MAJOR.$((MINOR + 1)).0" ;;
    major) echo "$((MAJOR + 1)).0.0" ;;
  esac
}

validate_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# SPEC is either a literal X.Y.Z or a bump kind.
IS_BUMP_KIND=false
case "$SPEC" in
  patch|minor|major) IS_BUMP_KIND=true ;;
esac

if ! $IS_BUMP_KIND && ! validate_semver "$SPEC"; then
  log_error "invalid version '$SPEC' (expected X.Y.Z or patch|minor|major)"
  exit 1
fi

# Apply overrides' validity
for pair in "backend:$OVERRIDE_BACKEND" "frontend:$OVERRIDE_FRONTEND"; do
  comp="${pair%%:*}"; val="${pair##*:}"
  if [[ -n "$val" ]] && ! validate_semver "$val"; then
    log_error "invalid --$comp override '$val'"
    exit 1
  fi
done

log_info "resolving target versions"

declare -A TARGET=()

for comp in backend frontend; do
  current="$(${COMPONENT_READ[$comp]})"
  if [[ -z "$current" ]]; then
    log_error "could not read current version for $comp"
    exit 1
  fi

  override_var="OVERRIDE_${comp^^}"
  override="${!override_var}"

  if [[ -n "$override" ]]; then
    target="$override"
    source="override"
  elif $IS_BUMP_KIND; then
    target="$(bump_kind "$SPEC" "$current")"
    source="$SPEC (from $current)"
  else
    target="$SPEC"
    source="default"
  fi

  if [[ "$target" == "$current" ]]; then
    log_warn "  $comp: already at $current (skip)"
    TARGET[$comp]="$current"
    continue
  fi

  TARGET[$comp]="$target"
  echo "  $comp: $current → $target ($source)"
done

# Quick exit if nothing to do
ANY_CHANGED=false
for comp in backend frontend; do
  current="$(${COMPONENT_READ[$comp]})"
  if [[ "${TARGET[$comp]}" != "$current" ]]; then
    ANY_CHANGED=true
    break
  fi
done
if ! $ANY_CHANGED; then
  log_success "no changes needed"
  exit 0
fi

# ── Patch each component ─────────────────────────────────────────────────

patch_file() {
  local f="$1" old="$2" new="$3" mode="$4"
  # Escape dots in $old and $new — '.' in sed BRE matches any character,
  # which would corrupt unrelated numbers in files like uv.lock
  # (e.g. size = 181814 → size = 1.1.24 when bumping 1.1.1 → 1.1.2).
  local old_esc="${old//./\\.}"
  local new_esc="${new//./\\.}"
  # All modes are ANCHORED to the line shape of the project's own version slot.
  # The previous `plain) sed s/OLD/NEW/g` was a full-text regex that corrupted
  # dependency version strings (e.g. `langchain>=0.4.0` → `langchain>=0.4.1`
  # when bumping project 0.4.0 → 0.4.1).
  case "$mode" in
    json)   # npm: anchor to "version": "X.Y.Z" (key prefix) so dep values like
            # `"react": "0.4.0"` are not touched.
            sed -i "s/\"version\": \"$old_esc\"/\"version\": \"$new_esc\"/" "$f" ;;
    toml)   # TOML PEP 621: ^version = "X.Y.Z"
            sed -i "s/^version = \"$old_esc\"/version = \"$new_esc\"/" "$f" ;;
    python) # Python module: ^(__version__) = "X.Y.Z"
            sed -i "s/^\(__version__\) = \"$old_esc\"/\1 = \"$new_esc\"/" "$f" ;;
    plain)  # Whole-line X.Y.Z (e.g. backend/VERSION plain-text file)
            sed -i "s/^$old_esc\$/$new_esc/" "$f" ;;
    *)      log_error "  $f: unknown mode '$mode' (expected: json|toml|python|plain)"
            return 1 ;;
  esac
}

for comp in backend frontend; do
  current="$(${COMPONENT_READ[$comp]})"
  target="${TARGET[$comp]}"
  [[ "$target" == "$current" ]] && continue

  log_info "patching $comp ($current → $target)"
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    f="${entry%%|*}"
    mode="${entry##*|}"
    if [[ ! -f "$f" ]]; then
      log_warn "  $f (missing, skipped)"
      continue
    fi
    patch_file "$f" "$current" "$target" "$mode"
    log_success "  $f"
  done <<< "${COMPONENT_FILES[$comp]}"

  # Sync lockfile if the toolchain supports it
  if declare -F "${COMPONENT_SYNC[$comp]}" >/dev/null; then
    log_info "  syncing lockfile"
    if ${COMPONENT_SYNC[$comp]}; then
      log_success "  lockfile refreshed"
    else
      log_warn "  lockfile sync failed — run manually"
    fi
  fi
done

# ── Verify ──────────────────────────────────────────────────────────────
# Grep for stale version references in version-bearing contexts.

log_info "verifying"
STALE=""
for comp in backend frontend; do
  current="$(${COMPONENT_READ[$comp]})"
  target="${TARGET[$comp]}"
  # Find any file under $ROOT_DIR whose target version string still appears
  # in a version-bearing context. Catches missed files.
  hits=$(grep -rEn --include='*.toml' --include='*.json' --include='*.py' \
    -e "^\"?v?$target\"? *=" \
    "$ROOT_DIR" 2>/dev/null \
    | awk -F: '{print $1}' \
    | sort -u || true)
  # Now check which of those still contain the OLD version (genuine stale refs).
  # Lockfiles are excluded — they legitimately retain old transitive dep versions
  # (e.g. pathspec 1.1.1 is correct even when the project version jumps to 1.2.0).
  for f in $hits; do
    [[ -f "$f" ]] || continue
    [[ "$f" =~ (uv|package-lock)\.lock$ ]] && continue
    if grep -q "$current" "$f" 2>/dev/null; then
      STALE+="$f (still has $current)"$'\n'
    fi
  done
done

if [[ -n "$STALE" ]]; then
  log_error "stale references detected:"
  echo "$STALE" | sed 's/^/    /'
  exit 1
fi
log_success "  no stale references"

# ── Diff summary ────────────────────────────────────────────────────────

echo
git --no-pager diff --stat

# ── Suggested commit message ────────────────────────────────────────────

NEW_VERSIONS=()
for comp in backend frontend; do
  current="$(${COMPONENT_READ[$comp]})"
  target="${TARGET[$comp]}"
  [[ "$target" != "$current" ]] && NEW_VERSIONS+=("$comp:$current→$target")
done

COMMON=""
for comp in backend frontend; do
  v="${TARGET[$comp]}"
  [[ -n "$v" && -z "$COMMON" ]] && COMMON="$v"
done

if [[ ${#NEW_VERSIONS[@]} -eq 2 ]]; then
  COMMIT_MSG="chore: 升级版本到 v$COMMON"
else
  COMMIT_MSG="chore: 升级版本"
  for nv in "${NEW_VERSIONS[@]}"; do
    COMMIT_MSG+=" ($nv)"
  done
fi

echo
log_info "next: review the diff above, then commit/tag/push manually:"
echo "    git add -A"
echo "    git commit -m \"$COMMIT_MSG\""
if [[ ${#NEW_VERSIONS[@]} -eq 2 ]]; then
  echo "    git tag -a v$COMMON -m \"...\""
  echo "    git push origin main && git push origin v$COMMON"
fi

