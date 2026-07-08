#!/bin/bash
# scripts/install-skills-to-projects.sh — 把 urywu-skills 的 skill 装到多个项目（Git Bash / WSL 版）
#
# PowerShell 等价版本：scripts/install-skills-to-projects.ps1（功能同步，命令行参数完全相同）
#
# 默认行为：装本仓库全部托管的 skill（当前 = fastapi-vue-version-bump + playwright-cli）。
# 可选参数：指定要装的 skill 名称（variadic，可多个），覆盖默认列表。
#
# Usage:
#   ./scripts/install-skills-to-projects.sh                                                # 装全部 skill 到 4 个默认项目
#   ./scripts/install-skills-to-projects.sh fastapi-vue-version-bump                       # 只装一个
#   ./scripts/install-skills-to-projects.sh fastapi-vue-version-bump playwright-cli       # 一次装多个
#
# 目标项目（Windows 路径，Git Bash 下可用）：
#   G:/Projects/projects_ai/audio2text
#   G:/Projects/projects_ai/data_sim_card_purchase_provide_data
#   G:/Projects/projects_ai/openlink
#   G:/Projects/projects_ai_skills_plugins/urywu-skills
#
# 幂等：skillslm install 在目标已存在时会覆盖（fs.rmSync 后 copy），可重复运行。
# npx -y：自动确认 skillslm@2.0.0 首次安装的 npm 提示，可无人值守运行。
#
# 加新 skill 时：把名字加到下方 ALL_SKILLS 数组即可（保持两个脚本同步）。

set -e

REPO="UryWu/urywu-skills"
AGENT="claude-code"

# 本仓库托管的全部 skill（默认安装列表）
ALL_SKILLS=(
    fastapi-vue-version-bump
    # playwright-cli
)

# 默认装全部；传参则覆盖
if [ $# -eq 0 ]; then
    SKILLS=("${ALL_SKILLS[@]}")
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

# 拼装 --skill 参数（variadic）
SKILL_ARGS=()
for s in "${SKILLS[@]}"; do
    SKILL_ARGS+=("--skill" "$s")
done

# 逐个安装
for project in "${PROJECTS[@]}"; do
    if [ ! -d "$project" ]; then
        echo "⚠  跳过（目录不存在）: $project"
        continue
    fi
    echo "▶  正在安装到: $project"
    echo "   skills:${SKILLS[*]}"
    (cd "$project" && npx -y skillslm install "$REPO" "${SKILL_ARGS[@]}" --agent "$AGENT" --yes)
    echo ""
done

echo "✓  全部完成（${#PROJECTS[@]} 个项目，${#SKILLS[@]} 个 skill）"