#!/bin/bash
# scripts/switch-to-global-install.sh — 把 skill 从项目级切到全局（Git Bash / WSL 版）
#
# PowerShell 等价版本：scripts/switch-to-global-install.ps1
#
# 操作流程：
#   Step 1: 从默认 4 个项目里移除 skill 的项目级副本
#   Step 2: 用 --global 装一次到 ~/.claude/skills/
#
# Usage:
#   ./scripts/switch-to-global-install.sh                                       # 切 fastapi-vue-version-bump
#   ./scripts/switch-to-global-install.sh playwright-cli                        # 切 playwright-cli
#   ./scripts/switch-to-global-install.sh fastapi-vue-version-bump playwright-cli   # 一次切多个
#
# 默认目标项目（要切的项目）：
#   G:/Projects/projects_ai/audio2text
#   G:/Projects/projects_ai/data_sim_card_purchase_provide_data
#   G:/Projects/projects_ai/openlink
#   G:/Projects/projects_ai_skills_plugins/urywu-skills
#
# 危险：此脚本会 rm -rf 项目里的 .claude/skills/<name>。运行前确认你已经备份
# 或者接受"用全局版覆盖"。

set -e

REPO="UryWu/urywu-skills"
AGENT="claude-code"

# 默认 skill
if [ $# -eq 0 ]; then
    SKILLS=(fastapi-vue-version-bump)
else
    SKILLS=("$@")
fi

# 目标项目列表
PROJECTS=(
    "G:/Projects/projects_ai/audio2text"
    "G:/Projects/projects_ai/data_sim_card_purchase_provide_data"
    "G:/Projects/projects_ai/openlink"
    "G:/Projects/projects_ai_skills_plugins/urywu-skills"
)

# Step 1: 移除项目级副本
echo "=== Step 1: 移除项目级副本 ==="
for project in "${PROJECTS[@]}"; do
    if [ ! -d "$project" ]; then
        echo "⚠  跳过（项目不存在）: $project"
        continue
    fi
    for skill in "${SKILLS[@]}"; do
        target="$project/.claude/skills/$skill"
        if [ -d "$target" ]; then
            echo "  rm -rf $target"
            rm -rf "$target"
        else
            echo "  - 不存在，跳过: $target"
        fi
    done
done
echo ""

# Step 2: 全局安装
echo "=== Step 2: 全局安装 ==="
SKILL_ARGS=()
for s in "${SKILLS[@]}"; do
    SKILL_ARGS+=("--skill" "$s")
done
echo "   skills:${SKILLS[*]}"
npx -y skillslm install "$REPO" "${SKILL_ARGS[@]}" --agent "$AGENT" --global --yes
echo ""

echo "✓ 完成（${#SKILLS[@]} 个 skill 已切到全局 ~/.claude/skills/）"
echo ""
echo "回退方案：如需回到项目级，运行："
echo "  ./scripts/install-skills-to-projects.sh ${SKILLS[*]}"