#!/bin/bash
# ==============================================================================
# scripts/bump_version.sh — 双组件版本号统一升降（Git Bash / WSL 版）
# ==============================================================================
#
# 作用：在 2 个 component（默认 backend + frontend）里统一升/降版本号，
#       自动 sed 改版本号 + 重新生成 lockfile + 校验无残留旧版本。
#
# 镜像版本：scripts/bump_version.ps1（PowerShell 版），功能完全同步。
#             改本脚本前先看 AGENTS.md 的红线章节，改完跑 test-patch-file.{sh,ps1}。
#
# 默认 component 拓扑：
#   - backend  (Python / FastAPI · uv lock)
#       source-of-truth: backend/pyproject.toml (PEP 621 `version = "..."`)
#       同步文件：backend/VERSION, backend/app/main.py, backend/app/schemas/types.py,
#                backend/app/api/endpoints/health.py
#   - frontend (Vue 3 · npm install)
#       source-of-truth: frontend/package.json (`"version": "..."`)
#
# Usage:
#   ./scripts/bump_version.sh 1.2.0                         # 全部 component → 1.2.0
#   ./scripts/bump_version.sh 1.2.0 --backend 1.1.5         # backend 1.1.5, frontend 1.2.0
#   ./scripts/bump_version.sh patch                         # 全部 component 自增 patch
#   ./scripts/bump_version.sh patch --frontend minor        # backend += patch, frontend += minor
#
# 运行后流程（人工，不进脚本）：
#   git diff          # 检查改动是否符合预期
#   git add -A
#   git commit -m "chore: 升级版本到 v1.2.0"
#   git tag -a v1.2.0 -m "v1.2.0"
#   git push origin main && git push origin v1.2.0
#
# 关键不变量（修改前请读 AGENTS.md 的「bump_version 的 mode 系统」一节）：
#   1. ❌ 绝不能恢复 "裸 sed s/OLD/NEW/g"——会把 langchain>=0.4.0 改成 langchain>=0.4.1
#   2. 4 个 mode (toml/python/plain/json) 各自锚定到 version 行/键，禁止去掉锚定
#   3. lockfile (uv.lock / package-lock.json) 绝不进 patch 列表——只能让
#      `uv lock` / `npm install` 重生成（避免 sed 破坏 transitive dep version）
#   4. commit / tag / push 不进脚本——留给人工写有上下文的 message
#
# 加第 3 个 component（如 browser extension）：
#   - COMPONENT_FILES / COMPONENT_READ / COMPONENT_SYNC 加一项
#   - 加 read_version_<name>() 和 sync_lock_<name() 函数
#   - 把 [[ ${#NEW_VERSIONS[@]} -eq 2 ]] 这种 count 检查改成 3
#   - 见 SKILL.md 的 "Adding a third component" 章节
# ==============================================================================

# `set -e`：任何命令失败立即退出
# 这是 release 工具：宁可全失败也不要半成功留下脏 lockfile / 部分 sed 后的文件
set -e

# ----------------------------------------------------------------------------
# 路径定位
# ----------------------------------------------------------------------------

# BASH_SOURCE[0] 是当前脚本路径；cd 到脚本所在目录，然后 dirname 取上一层
# （也就是项目根：scripts/ → ../）。这样无论从哪个 cwd 调脚本都能正确锁住路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# cd 到项目根——所有相对路径（backend/pyproject.toml 等）都基于此
cd "$ROOT_DIR"

# ----------------------------------------------------------------------------
# 日志工具
# ----------------------------------------------------------------------------
# 彩色输出比裸 echo 更易扫读。色码用 ANSI 转义；Windows Git Bash 10.0+ 默认支持
RED='\033[0;31m'    # 错误
GREEN='\033[0;32m'  # 成功
YELLOW='\033[1;33m' # 警告
BLUE='\033[0;34m'   # 信息
NC='\033[0m'        # No Color（重置）

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ----------------------------------------------------------------------------
# 参数解析
# ----------------------------------------------------------------------------
# 支持：
#   - 位置参数 1：版本 spec（X.Y.Z 或 patch|minor|major）
#   - --backend X.Y.Z / --frontend X.Y.Z：单独 override 某个 component 的目标
#   - -h / --help：打印用法
#
# 用 while-shift 模式：每次循环处理一个 token，shift 掉已处理的
# 未知参数 → 报错退出（避免 typo 默默被吞）

SPEC=""              # 主 spec（位置参数 1）
OVERRIDE_BACKEND=""  # --backend X.Y.Z
OVERRIDE_FRONTEND="" # --frontend X.Y.Z

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend)   OVERRIDE_BACKEND="$2";   shift 2 ;;  # 消耗 2 个 token
    --frontend)  OVERRIDE_FRONTEND="$2";  shift 2 ;;
    -h|--help)
      # 把脚本头注释（line 3-22）抽出来当 help text；sed 把开头的 # 去掉
      sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      # 第一个非选项参数是 SPEC；如果已经有 SPEC 了说明用户传多了位置参数
      if [[ -n "$SPEC" ]]; then
        log_error "unexpected positional argument: $1 (only one of X.Y.Z | patch | minor | major allowed)"
        exit 1
      fi
      SPEC="$1"
      shift
      ;;
  esac
done

# SPEC 是必需的——没传就别瞎跑
if [[ -z "$SPEC" ]]; then
  log_error "missing version spec: pass X.Y.Z or patch|minor|major"
  exit 1
fi

# ----------------------------------------------------------------------------
# Component 定义
# ----------------------------------------------------------------------------
# 3 个 declare -A 哈希表共享同一个 key（component 名：backend / frontend）：
#   COMPONENT_FILES[<name>]  — 多行字符串，每行 "path|mode"
#   COMPONENT_READ[<name>]   — 读当前版本的函数名（输出 X.Y.Z 到 stdout）
#   COMPONENT_SYNC[<name>]   — 改完文件后重生成 lockfile 的函数名
#
# 这样新加 component 只动 3 个地方，不用改主循环。

# read_version_<name>：打印当前版本到 stdout
# - backend:  pyproject.toml 是 PEP 621 `version = "..."` 格式
# - frontend: package.json 是 JSON `"version": "..."`
# 用 grep + sed 解出来；比 awk/JSON 解析器简单，足够稳定
read_version_backend() {
  grep -E '^version = "' backend/pyproject.toml | head -1 | sed -E 's/^version = "(.+)"$/\1/'
}
read_version_frontend() {
  grep -E '"version":' frontend/package.json | head -1 | sed -E 's/.*"version": *"([^"]+)".*/\1/'
}

# sync_lock_<name>：改完版本号后重新生成 lockfile
# - uv lock   读 pyproject.toml 更新 uv.lock；transitive deps 不动（正是要的）
# - npm install 读 package.json 更新 package-lock.json；同样不动 transitive
#
# ❌ 不要把 uv.lock / package-lock.json 加进 COMPONENT_FILES！sed 会破坏
#    transitive deps（如 pathspec 1.1.1 出现在 uv.lock 里时 sed 会改成 1.2.0）
sync_lock_backend()   { (cd backend   && uv lock            >/dev/null 2>&1); }
sync_lock_frontend()  { (cd frontend  && npm install --silent --no-audit --no-fund >/dev/null 2>&1); }

# COMPONENT_FILES：每个 component 要 patch 的文件列表
# 格式：多行字符串，每行 "相对路径|patch_mode"
# mode 决定 sed 锚定方式（详见 patch_file() 函数）：
#   toml   → ^version = "X.Y.Z"            (PEP 621)
#   python → ^(__version__) = "X.Y.Z"       (Python module)
#   plain  → ^X.Y.Z$                        (整行)
#   json   → "version": "X.Y.Z"             (npm key 前缀)
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

# ----------------------------------------------------------------------------
# 解析 SPEC：算出每个 component 的目标版本
# ----------------------------------------------------------------------------

# bump_kind：给定 kind（patch|minor|major）和当前 X.Y.Z，返回新版本
# 例：bump_kind patch 1.2.3 → "1.2.4"
# 例：bump_kind major 1.2.3 → "2.0.0"（minor 和 patch 段归零）
bump_kind() {
  # $1: kind (patch|minor|major), $2: current (X.Y.Z) → echoes new
  local kind="$1" cur="$2"
  # IFS='.' 临时改分隔符，把 "1.2.3" 拆成 1 / 2 / 3 三个变量
  IFS='.' read -r MAJOR MINOR PATCH <<< "$cur"
  case "$kind" in
    patch) echo "$MAJOR.$MINOR.$((PATCH + 1))" ;;
    minor) echo "$MAJOR.$((MINOR + 1)).0" ;;   # patch 段归零
    major) echo "$((MAJOR + 1)).0.0" ;;        # minor + patch 都归零
  esac
}

# validate_semver：是否是 X.Y.Z 格式（数字.数字.数字）
# 用 bash regex（[[ =~ ]]），比 egrep 简单
validate_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# SPEC 可能是 "1.2.3" 也可能是 "patch"——区分两种 mode
IS_BUMP_KIND=false
case "$SPEC" in
  patch|minor|major) IS_BUMP_KIND=true ;;
esac

# SPEC 既不是 bump kind 也不是合法 semver → 报错退出
if ! $IS_BUMP_KIND && ! validate_semver "$SPEC"; then
  log_error "invalid version '$SPEC' (expected X.Y.Z or patch|minor|major)"
  exit 1
fi

# 校验 --backend / --frontend override 是否合法 semver
for pair in "backend:$OVERRIDE_BACKEND" "frontend:$OVERRIDE_FRONTEND"; do
  comp="${pair%%:*}"; val="${pair##*:}"   # split on first ':'
  if [[ -n "$val" ]] && ! validate_semver "$val"; then
    log_error "invalid --$comp override '$val'"
    exit 1
  fi
done

log_info "resolving target versions"

# TARGET[<comp>] = 每个 component 的目标版本（X.Y.Z 字符串）
declare -A TARGET=()

for comp in backend frontend; do
  # 调用 reader 函数读当前版本
  current="$(${COMPONENT_READ[$comp]})"
  if [[ -z "$current" ]]; then
    # 读不到版本 = pyproject.toml 缺 version 字段 / 文件不存在 / 格式错
    # 这是用户侧配置 bug，不是脚本能修复的
    log_error "could not read current version for $comp"
    exit 1
  fi

  # 检查 override：${comp^^} 把 comp 转大写，匹配 OVERRIDE_BACKEND / OVERRIDE_FRONTEND
  # bash 的间接变量展开：${!var} 展开 var 的值作为另一个变量名
  override_var="OVERRIDE_${comp^^}"
  override="${!override_var}"

  # 三选一优先级：override > bump kind > default
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

  # 目标 == 当前 → 跳过（不需要改）
  if [[ "$target" == "$current" ]]; then
    log_warn "  $comp: already at $current (skip)"
    TARGET[$comp]="$current"
    continue
  fi

  TARGET[$comp]="$target"
  echo "  $comp: $current → $target ($source)"
done

# Quick exit：如果两个 component 都不用改，直接退出
# 节省时间 + 给用户清晰反馈
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

# ----------------------------------------------------------------------------
# 改文件 + 重生成 lockfile
# ----------------------------------------------------------------------------
#
# patch_file 是核心：4 个 mode 各自的 sed 锚定
# 设计原则：永远只改"项目自身的 version slot"，绝不改任何依赖版本号

patch_file() {
  local f="$1" old="$2" new="$3" mode="$4"

  # 转义 sed BRE 元字符：'.' 在 sed BRE 里匹配任意字符
  # 如果不转义，1.1.1 → 1.1.2 会把 "181814" 误改成 "1.1.24"（灾难）
  local old_esc="${old//./\\.}"
  local new_esc="${new//./\\.}"

  # ⚠️  关键修复历史：
  # 旧版 plain 模式用 `sed s/OLD/NEW/g` 是全文替换，会把
  # pyproject.toml 里的 `langchain>=0.4.0` 也改成 `langchain>=0.4.1`。
  # 现在所有 mode 都锚定到 version 行/键，绝不"全文匹配 X.Y.Z"。
  case "$mode" in
    json)   # npm package.json：锚定到 `"version": "X.Y.Z"`（带 key 前缀）
            # 这样 `"react": "0.4.0"` 这种依赖 version 不会被误改
            sed -i "s/\"version\": \"$old_esc\"/\"version\": \"$new_esc\"/" "$f" ;;
    toml)   # TOML PEP 621：锚定到行首 `version = "X.Y.Z"`
            sed -i "s/^version = \"$old_esc\"/version = \"$new_esc\"/" "$f" ;;
    python) # Python module：锚定到行首 `__version__ = "X.Y.Z"`
            # 用 \1 反向引用保留变量名（避免 `version = "..."` 这种无前缀版本被误改）
            sed -i "s/^\(__version__\) = \"$old_esc\"/\1 = \"$new_esc\"/" "$f" ;;
    plain)  # 整行只有版本号（backend/VERSION 这种纯文本文件）
            sed -i "s/^$old_esc\$/$new_esc/" "$f" ;;
    *)      log_error "  $f: unknown mode '$mode' (expected: json|toml|python|plain)"
            return 1 ;;
  esac
}

# 主循环：对每个 component
#   1. 对 COMPONENT_FILES 里的每个文件调 patch_file
#   2. 调用 sync_lock_<name>() 重生成 lockfile
for comp in backend frontend; do
  current="$(${COMPONENT_READ[$comp]})"
  target="${TARGET[$comp]}"
  # 该 component 不需要改就跳过
  [[ "$target" == "$current" ]] && continue

  log_info "patching $comp ($current → $target)"
  # COMPONENT_FILES[$comp] 是多行字符串，用 here-string (<<<) 喂给 while read
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue  # 空行跳过
    # 拆 "path|mode" → 路径 + mode
    f="${entry%%|*}"      # 第一个 | 之前
    mode="${entry##*|}"    # 最后一个 | 之后
    if [[ ! -f "$f" ]]; then
      # 文件不存在（比如用户自定义项目里某些文件没有）—— 只警告不退出
      log_warn "  $f (missing, skipped)"
      continue
    fi
    patch_file "$f" "$current" "$target" "$mode"
    log_success "  $f"
  done <<< "${COMPONENT_FILES[$comp]}"

  # 重生成 lockfile（如有定义 sync_lock_<name>()）
  # declare -F <funcname> 检查函数是否已定义；用于支持某些 component 没有 lockfile
  # 失败只警告不退出——lockfile 问题可手动跑 `uv lock` / `npm install` 修复
  if declare -F "${COMPONENT_SYNC[$comp]}" >/dev/null; then
    log_info "  syncing lockfile"
    if ${COMPONENT_SYNC[$comp]}; then
      log_success "  lockfile refreshed"
    else
      log_warn "  lockfile sync failed — run manually"
    fi
  fi
done

# ----------------------------------------------------------------------------
# 验证：搜残留旧版本
# ----------------------------------------------------------------------------
# 用 grep 找出还有旧版本字符串的 .toml / .json / .py 文件（排除 lockfile）
# 这是个安全网：如果 COMPONENT_FILES 漏登记某个文件，这里会报错提示

log_info "verifying"
STALE=""
for comp in backend frontend; do
  current="$(${COMPONENT_READ[$comp]})"
  target="${TARGET[$comp]}"
  # 找出所有包含新版本 X.Y.Z 的文件（v? 前缀容忍 `version = ...` 和 `v1.2.0` 两种写法）
  # 命中文件可能还在用旧版本（说明我们漏改了）
  hits=$(grep -rEn --include='*.toml' --include='*.json' --include='*.py' \
    -e "^\"?v?$target\"? *=" \
    "$ROOT_DIR" 2>/dev/null \
    | awk -F: '{print $1}' \
    | sort -u || true)
  # 对每个命中文件，检查是否还含旧版本字符串
  # ⚠️  lockfile 排除：uv.lock / package-lock.json 合法保留旧版本（transitive deps）
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

# ----------------------------------------------------------------------------
# Diff 摘要 + 建议 commit message
# ----------------------------------------------------------------------------
# 打印 git diff --stat 让人眼扫一下改动量
# 然后给个建议的 commit message（用户可改写）

echo
git --no-pager diff --stat

# 收集变动的 component（current → target）
NEW_VERSIONS=()
for comp in backend frontend; do
  current="$(${COMPONENT_READ[$comp]})"
  target="${TARGET[$comp]}"
  [[ "$target" != "$current" ]] && NEW_VERSIONS+=("$comp:$current→$target")
done

# 找公共版本（用于 vX.Y.Z 形式的 commit message）
COMMON=""
for comp in backend frontend; do
  v="${TARGET[$comp]}"
  [[ -n "$v" && -z "$COMMON" ]] && COMMON="$v"
done

# 两 component 都改 → 用 "升级版本到 vX.Y.Z"；只改一个 → 列出来
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