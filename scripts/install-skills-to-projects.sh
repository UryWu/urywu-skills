#!/bin/bash
# ==============================================================================
# scripts/install-skills-to-projects.sh
# ==============================================================================
# 作用：把 urywu-skills 仓库托管的 skill 批量安装到多个本地项目（项目级作用域）。
#
# 镜像版本：scripts/install-skills-to-projects.ps1（PowerShell 版，功能完全同步）。
#             修改本脚本时请同步改 ps1，并跑两边冒烟测试。
#
# 默认行为：
#   - 无参数：装本仓库 ALL_SKILLS 数组里登记的全部 skill
#   - 传参  ：装指定的 skill 名称（variadic，可多个），覆盖默认列表
#
# 安装作用域：项目级（./.claude/skills/<skill-name>/），跟随每个项目的 cwd。
#             如需全局安装（~/.claude/skills/），用 switch-to-global-install.sh。
#
# Usage:
#   ./scripts/install-skills-to-projects.sh                                                # 装 ALL_SKILLS 列表全部
#   ./scripts/install-skills-to-projects.sh fastapi-vue-version-bump                       # 只装一个
#   ./scripts/install-skills-to-projects.sh fastapi-vue-version-bump playwright-cli       # 一次装多个
#
# 目标项目（Windows Git Bash 风格路径）：
#   G:/Projects/projects_ai/audio2text
#   G:/Projects/projects_ai/data_sim_card_purchase_provide_data
#   G:/Projects/projects_ai/openlink
#   G:/Projects/projects_ai_skills_plugins/urywu-skills
#
# 关键不变量（修改前请读 AGENTS.md）：
#   1. 必须用 `npx -y`（不要去掉 -y），否则首次运行会卡在 npm 的 "Ok to proceed?" 提示
#   2. PROJECTS 数组路径必须存在；不存在的会跳过（不报错），日志输出 "⚠  跳过"
#   3. skillslm install 在目标已存在时是覆盖式（fs.rmSync 后 copy），所以脚本天然幂等
#   4. 加新 skill 时只需往 ALL_SKILLS 数组里加名字；不要忘了同步 ps1 版本
#
# 冒烟测试：
#   bash scripts/install-skills-to-projects.sh
#   应该看到 4 行 "▶  正在安装到: ..." 加 4 行 "✓ fastapi-vue-version-bump → Claude Code"
# ==============================================================================

# `set -e`：任何命令失败立即退出，避免部分失败留下半生不熟的 state。
# 这对破坏性操作（rm/网络请求）尤其重要——宁可全失败也不要半成功。
set -e

# ----------------------------------------------------------------------------
# 配置区（按需修改）
# ----------------------------------------------------------------------------

# 仓库 shorthand（owner/repo 格式），传给 skillslm install。
# skillslm 会自动从 GitHub 拉取对应仓库的 skills/ 子目录。
REPO="UryWu/urywu-skills"

# 目标 agent。claude-code 对应路径 .claude/skills/；其他可选：cursor / codex / opencode / amp / kilo / roo / goose / antigravity
AGENT="claude-code"

# 本仓库当前托管的全部 skill（默认安装列表）。
# ⚠️  加新 skill 时在这里追加名字（保持 ps1 同步）。如不希望默认装就加 # 注释掉（参考 playwright-cli）。
ALL_SKILLS=(
    fastapi-vue-version-bump
    # playwright-cli
)

# 目标项目列表（Git Bash 风格 Windows 路径）。
# 这些项目会被 (cd $project && npx skillslm install) 一一处理。
# 注意：最后一个就是 urywu-skills 仓库自身，方便自举。
PROJECTS=(
    "G:/Projects/projects_ai/audio2text"
    "G:/Projects/projects_ai/data_sim_card_purchase_provide_data"
    "G:/Projects/projects_ai/openlink"
    "G:/Projects/projects_ai_skills_plugins/urywu-skills"
)

# ----------------------------------------------------------------------------
# 解析参数：决定本次要装哪些 skill
# ----------------------------------------------------------------------------

# 默认装 ALL_SKILLS 列表全部；用户传参则覆盖（variadic）。
# 例子：
#   $ ./install-skills-to-projects.sh                  → SKILLS = ALL_SKILLS 全集
#   $ ./install-skills-to-projects.sh playwright-cli   → SKILLS = (playwright-cli)
#   $ ./install-skills-to-projects.sh a b c            → SKILLS = (a b c)
if [ $# -eq 0 ]; then
    # 空参数 → 展开 ALL_SKILLS 数组到 SKILLS
    # 用 "${ARR[@]}" 加双引号防 glob 扩展 + 单词分割
    SKILLS=("${ALL_SKILLS[@]}")
else
    # "$@" 把所有位置参数原样保留（每个参数独立成词）
    SKILLS=("$@")
fi

# ----------------------------------------------------------------------------
# 拼装 --skill 参数数组（variadic）
# ----------------------------------------------------------------------------
# skillslm install 的 --skill 选项是 variadic：--skill a --skill b --skill c
# 我们要把 SKILLS 数组展平成 ["--skill", "a", "--skill", "b", ...] 形式
# 这样后面 "${SKILL_ARGS[@]}" 展开时会作为独立参数传给 npx。
#
# 如果不展开，shell 会把 "--skill a" 当作一个参数，skillslm 会解析失败。
SKILL_ARGS=()
for s in "${SKILLS[@]}"; do
    SKILL_ARGS+=("--skill" "$s")
done

# ----------------------------------------------------------------------------
# 逐项目安装
# ----------------------------------------------------------------------------
# 对每个项目：
#   1. 检查目录是否存在（不存在就跳过，不报错）
#   2. 切到该目录作为 cwd（skillslm 装到 cwd 下的 .claude/skills/）
#   3. 调用 skillslm install
#   4. 切回原目录（set -e 失败时会自动退出，子 shell 不影响父 cwd）
for project in "${PROJECTS[@]}"; do
    # 项目目录不存在（比如新 clone 的机器还没建 audio2text/）就跳过
    # 不报错是设计选择：脚本可在任意数量的现存项目上跑
    if [ ! -d "$project" ]; then
        echo "⚠  跳过（目录不存在）: $project"
        continue
    fi
    echo "▶  正在安装到: $project"
    echo "   skills:${SKILLS[*]}"

    # 子 shell (cd ... && npx ...) 让 cwd 切换不影响外层
    # npx -y：自动确认 skillslm@2.0.0 的首次安装提示
    # "${SKILL_ARGS[@]}"：展开成独立参数（变参），见上方拼装说明
    # --yes：跳过 skillslm 自己的二次确认
    # --agent "$AGENT"：限定目标 agent（不传会报错或装错位置）
    (cd "$project" && npx -y skillslm install "$REPO" "${SKILL_ARGS[@]}" --agent "$AGENT" --yes)
    echo ""
done

# 最终汇总
echo "✓  全部完成（${#PROJECTS[@]} 个项目，${#SKILLS[@]} 个 skill）"