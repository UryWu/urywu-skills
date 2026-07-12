#!/bin/bash
# scripts/test-patch-file.sh — 回归测试：patch_file() 只改项目的 version 行，不改依赖版本号
#
# 这是针对"裸 sed s/OLD/NEW/g 把 langchain>=0.4.0 也改了"那个 bug 的回归测试。
# 跑 ./scripts/test-patch-file.sh 会建临时文件、调用 patch_file、断言结果、清干净。
#
# 用法: ./scripts/test-patch-file.sh

set -e

# 把 patch_file() 复制过来（脚本里它不是单独的 lib），保持与 bump_version.sh 一致
patch_file() {
  local f="$1" old="$2" new="$3" mode="$4"
  local old_esc="${old//./\\.}"
  local new_esc="${new//./\\.}"
  case "$mode" in
    json)   sed -i "s/\"version\": \"$old_esc\"/\"version\": \"$new_esc\"/" "$f" ;;
    toml)   sed -i "s/^version = \"$old_esc\"/version = \"$new_esc\"/" "$f" ;;
    python) sed -i "s/^\(__version__\) = \"$old_esc\"/\1 = \"$new_esc\"/" "$f" ;;
    plain)  sed -i "s/^$old_esc\$/$new_esc/" "$f" ;;
    *)      echo "FAIL: unknown mode '$mode'" >&2; return 1 ;;
  esac
}

TMPDIR="$(mktemp -d)"
trap "rm -rf $TMPDIR" EXIT

PASS=0
FAIL=0

assert_file_contains() {
    local file="$1" needle="$2" desc="$3"
    if grep -qF "$needle" "$file"; then
        echo "  ✓ $desc"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $desc (expected: '$needle' in $file)"
        echo "    --- file content ---"
        sed 's/^/      /' "$file"
        echo "    --------------------"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_not_contains() {
    local file="$1" needle="$2" desc="$3"
    if ! grep -qF "$needle" "$file"; then
        echo "  ✓ $desc"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $desc (did NOT expect: '$needle' in $file)"
        echo "    --- file content ---"
        sed 's/^/      /' "$file"
        echo "    --------------------"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Test 1: pyproject.toml (toml mode) ==="
cat > "$TMPDIR/pyproject.toml" <<'EOF'
[project]
name = "myapp"
version = "0.4.0"
dependencies = [
    "langchain>=0.4.0",
    "fastapi>=0.100.0",
    "pydantic~=0.4.0",
]
EOF
patch_file "$TMPDIR/pyproject.toml" "0.4.0" "0.4.1" "toml"
assert_file_contains     "$TMPDIR/pyproject.toml" 'version = "0.4.1"' "version 行更新了"
assert_file_not_contains "$TMPDIR/pyproject.toml" 'langchain>=0.4.1' "langchain dep 没被改"
assert_file_contains     "$TMPDIR/pyproject.toml" 'langchain>=0.4.0' "langchain dep 保持原样"
assert_file_not_contains "$TMPDIR/pyproject.toml" 'pydantic~=0.4.1' "pydantic dep 没被改"
assert_file_contains     "$TMPDIR/pyproject.toml" 'pydantic~=0.4.0' "pydantic dep 保持原样"

echo ""
echo "=== Test 2: plain text VERSION file (plain mode) ==="
echo "0.4.0" > "$TMPDIR/VERSION"
patch_file "$TMPDIR/VERSION" "0.4.0" "0.4.1" "plain"
content="$(cat "$TMPDIR/VERSION")"
if [[ "$content" == "0.4.1" ]]; then
    echo "  ✓ VERSION 文件整行被替换为 0.4.1"
    PASS=$((PASS + 1))
else
    echo "  ✗ VERSION 文件未正确更新（got '$content'）"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Test 3: Python __version__ (python mode) ==="
cat > "$TMPDIR/main.py" <<'EOF'
"""My app module."""

__version__ = "0.4.0"

# 别名/常量同名的旧版本不应该被改
SOME_DEP_VERSION = "0.4.0"
EOF
patch_file "$TMPDIR/main.py" "0.4.0" "0.4.1" "python"
assert_file_contains     "$TMPDIR/main.py" '__version__ = "0.4.1"' "__version__ 行更新了"
assert_file_not_contains "$TMPDIR/main.py" '__version__ = "0.4.0"' "__version__ 旧值被替换干净"
assert_file_contains     "$TMPDIR/main.py" 'SOME_DEP_VERSION = "0.4.0"' "其他变量的 0.4.0 不该被改"

echo ""
echo "=== Test 4: package.json (json mode) ==="
cat > "$TMPDIR/package.json" <<'EOF'
{
  "name": "myapp",
  "version": "0.4.0",
  "dependencies": {
    "react": "0.4.0",
    "vue": "3.0.0"
  }
}
EOF
patch_file "$TMPDIR/package.json" "0.4.0" "0.4.1" "json"
assert_file_contains     "$TMPDIR/package.json" '"version": "0.4.1"' "顶层 version 更新了"
assert_file_not_contains "$TMPDIR/package.json" '"react": "0.4.1"' "react dep 没被改"
assert_file_contains     "$TMPDIR/package.json" '"react": "0.4.0"' "react dep 保持原样"
assert_file_contains     "$TMPDIR/package.json" '"vue": "3.0.0"' "无关 vue dep 保持原样"

echo ""
echo "=== 汇总 ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
echo "✓ 所有测试通过"