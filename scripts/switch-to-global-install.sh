#!/bin/bash
# ==============================================================================
# scripts/switch-to-global-install.sh
# ==============================================================================
# 作用：把 skill 从"项目级作用域"（./.claude/skills/）切到"全局作用域"（~/.claude/skills/）。
#
# 镜像版本：scripts/switch-to-global-install.ps1（PowerShell 版，功能完全同步）。
#
# 操作流程：
#   Step 1 — 从默认 4 个项目里移除 skill 的项目级副本（rm -rf）
#   Step 2 — 用 --global 装一次到 ~/.claude/skills/
#
# ⚠️  危险操作：会 rm -rf 项目里的 .claude/skills/<name>。
#             运行前请确认：
#             - 你已经不需要项目级副本（customization 已合并到全局版）
#             - 或者你已经手动备份（虽然 skillslm 装的是纯静态文件，重装就能恢复）
#
# 为什么需要这步：
#   通用工具（如 playwright-cli）装全局更省心——一次装到处可用。
#   项目特定 skill 反而要保留项目级——避免污染其他项目。
#
# Usage:
#   ./scripts/switch-to-global-install.sh                                       # 切 fastapi-vue-version-bump
#   ./scripts/switch-to-global-install.sh playwright-cli                        # 切 playwright-cli
#   ./scripts/switch-to-global-install.sh fastapi-vue-version-bump playwright-cli   # 一次切多个
#
# 目标项目（要切的项目，与 install-skills-to-projects.sh 同步）：
#   G:/Projects/projects_ai/audio2text
#   G:/Projects/projects_ai/data_sim_card_purchase_provide_data
#   G:/Projects/projects_ai/openlink
#   G:/Projects/projects_ai_skills_plugins/urywu-skills
#
# 回退：再跑 install-skills-to-projects.sh 装回项目级即可。
#
# 关键不变量（修改前请读 AGENTS.md）：
#   1. 必须用 `npx -y ... --global --yes`（顺序：-y 全局确认、--global 全局装、--yes skillslm 二次确认）
#   2. ❌ 不要用 `npx skillslm update ... --global`：v2.0.0 的 update --global 是 broken 的，
#      会写到 cwd/.skills/ 而不是 ~/.claude/skills/（见 README 的「已知 bug」一节）。
# ==============================================================================

# `set -e`：rm -rf 失败或 npx 失败立即退出，避免半破坏状态
set -e

# ----------------------------------------------------------------------------
# 配置区
# ----------------------------------------------------------------------------

REPO="UryWu/urywu-skills"
AGENT="claude-code"

# 默认 skill
if [ $# -eq 0 ]; then
    SKILLS=(fastapi-vue-version-bump)
else
    SKILLS=("$@")
fi

# 目标项目列表（与 install-skills-to-projects.sh 保持同步）
PROJECTS=(
    "G:/Projects/projects_ai/audio2text"
    "G:/Projects/projects_ai/data_sim_card_purchase_provide_data"
    "G:/Projects/projects_ai/openlink"
    "G:/Projects/projects_ai_skills_plugins/urywu-skills"
)

# ----------------------------------------------------------------------------
# Step 1: 移除项目级副本
# ----------------------------------------------------------------------------
# 对每个项目 × 每个 skill：检查 $project/.claude/skills/<skill>/ 是否存在，
# 存在就 rm -rf，不存在就跳过（不算错）。
#
# 这里没把 npx -y 之类的 confirm 标志放在循环里——rm -rf 是直接执行的，
# 这是个 trade-off：要更安全可以把 rm 改成先 echo + 询问用户。
echo "=== Step 1: 移除项目级副本 ==="
for project in "${PROJECTS[@]}"; do
    # 项目目录不存在（比如新机器还没建 audio2text/）就跳过
    if [ ! -d "$project" ]; then
        echo "⚠  跳过（项目不存在）: $project"
        continue
    fi
    # 对每个 skill 都检查一遍（variadic）
    for skill in "${SKILLS[@]}"; do
        # Git Bash 风格的路径拼接
        target="$project/.claude/skills/$skill"
        if [ -d "$target" ]; then
            # 先 echo 出来让用户能看到要删什么，再实际删
            # 这是审计痕迹——比静默 rm 友好
            echo "  rm -rf $target"
            rm -rf "$target"
        else
            echo "  - 不存在，跳过: $target"
        fi
    done
done
echo ""

# ----------------------------------------------------------------------------
# Step 2: 全局安装
# ----------------------------------------------------------------------------
# 这一步直接调 skillslm install --global --yes。
# 不需要切到任何项目目录——全局装与 cwd 无关。
echo "=== Step 2: 全局安装 ==="

# 拼装 variadic --skill 参数（与 install-skills-to-projects.sh 同款逻辑）
# skillslm install 的 --skill 是 variadic：--skill a --skill b --skill c
# 必须展开成独立参数，否则会被当作单个参数解析失败。
SKILL_ARGS=()
for s in "${SKILLS[@]}"; do
    SKILL_ARGS+=("--skill" "$s")
done

echo "   skills:${SKILLS[*]}"
# ⚠️  关键：用 `install ... --global --yes`，不要用 `update ... --global`
# v2.0.0 的 update --global 是 broken 的（写入 cwd/.skills/ 而不是 ~/.claude/skills/）
# install 是覆盖式（fs.rmSync + copy），与 update 等效且无 bug
npx -y skillslm install "$REPO" "${SKILL_ARGS[@]}" --agent "$AGENT" --global --yes
echo ""

# 汇总 + 回退提示
echo "✓ 完成（${#SKILLS[@]} 个 skill 已切到全局 ~/.claude/skills/）"
echo ""
echo "回退方案：如需回到项目级，运行："
echo "  ./scripts/install-skills-to-projects.sh ${SKILLS[*]}"