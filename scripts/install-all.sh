#!/bin/bash
# scripts/install-all.sh — 一键把 urywu-skills 的 skill 装到多个项目
#
# 默认行为：把 fastapi-vue-version-bump 装到 4 个常用项目。
# 可选参数：要装的 skill 名称（variadic，可多个），不传则装 fastapi-vue-version-bump。
#
# Usage:
#   ./scripts/install-all.sh                                      # 装 fastapi-vue-version-bump 到 4 个默认项目
#   ./scripts/install-all.sh playwright-cli                      # 装 playwright-cli 到 4 个默认项目
#   ./scripts/install-all.sh fastapi-vue-version-bump playwright-cli   # 一次装多个
#
# 目标项目（Windows 路径，Git Bash 下可用）：
#   G:/Projects/projects_ai/audio2text
#   G:/Projects/projects_ai/data_sim_card_purchase_provide_data
#   G:/Projects/projects_ai/openlink
#   G:/Projects/projects_ai_skills_plugins/urywu-skills
#
# 幂等：skillslm install 在目标已存在时会覆盖（fs.rmSync 后 copy），可重复运行。

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

# 拼装 --skill 参数（variadic）
SKILL_ARGS=""
for s in "${SKILLS[@]}"; do
    SKILL_ARGS="$SKILL_ARGS --skill $s"
done

# 逐个安装
for project in "${PROJECTS[@]}"; do
    if [ ! -d "$project" ]; then
        echo "⚠  跳过（目录不存在）: $project"
        continue
    fi
    echo "▶  正在安装到: $project"
    echo "   skills:${SKILLS[*]}"
    (cd "$project" && npx skillslm install "$REPO" $SKILL_ARGS --agent "$AGENT" --yes)
    echo ""
done

echo "✓  全部完成（${#PROJECTS[@]} 个项目，${#SKILLS[@]} 个 skill）"