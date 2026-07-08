# scripts/install-skills-to-projects.ps1 — 把 urywu-skills 的 skill 装到多个项目（PowerShell 版）
#
# Bash 等价版本：scripts/install-skills-to-projects.sh（功能同步，命令行参数完全相同）
#
# 默认行为：装本仓库全部托管的 skill（当前 = fastapi-vue-version-bump + playwright-cli）。
# 可选参数：指定要装的 skill 名称（variadic，可多个），覆盖默认列表。
#
# Usage:
#   .\scripts\install-skills-to-projects.ps1                                                # 装全部 skill 到 4 个默认项目
#   .\scripts\install-skills-to-projects.ps1 fastapi-vue-version-bump                       # 只装一个
#   .\scripts\install-skills-to-projects.ps1 fastapi-vue-version-bump playwright-cli       # 一次装多个
#
# 目标项目（Windows 原生路径）：
#   G:\Projects\projects_ai\audio2text
#   G:\Projects\projects_ai\data_sim_card_purchase_provide_data
#   G:\Projects\projects_ai\openlink
#   G:\Projects\projects_ai_skills_plugins\urywu-skills
#
# 幂等：skillslm install 在目标已存在时会覆盖（fs.rmSync 后 copy），可重复运行。
# npx -y：自动确认 skillslm@2.0.0 首次安装的 npm 提示，可无人值守运行。
#
# 加新 skill 时：把名字加到下方 $AllSkills 数组即可（保持两个脚本同步）。

$ErrorActionPreference = "Stop"

$Repo = "UryWu/urywu-skills"
$Agent = "claude-code"

# 本仓库托管的全部 skill（默认安装列表）
$AllSkills = @(
    "fastapi-vue-version-bump",
    # "playwright-cli"
)

# 默认装全部；传参则覆盖
if ($args.Count -eq 0) {
    $Skills = $AllSkills
} else {
    $Skills = $args
}

# 目标项目列表（Windows 原生路径，用反斜杠）
$Projects = @(
    "G:\Projects\projects_ai\audio2text",
    "G:\Projects\projects_ai\data_sim_card_purchase_provide_data",
    "G:\Projects\projects_ai\openlink",
    "G:\Projects\projects_ai_skills_plugins\urywu-skills"
)

# 逐个安装
foreach ($project in $Projects) {
    if (-not (Test-Path -LiteralPath $project -PathType Container)) {
        Write-Host "⚠  跳过（目录不存在）: $project"
        continue
    }

    Write-Host "▶  正在安装到: $project"
    Write-Host "   skills: $($Skills -join ', ')"

    # 拼装 variadic --skill 参数（用 splat @skillArgs 传给 npx）
    $skillArgs = @()
    foreach ($s in $Skills) {
        $skillArgs += "--skill"
        $skillArgs += $s
    }

    Push-Location -LiteralPath $project
    try {
        & npx -y skillslm install $Repo @skillArgs --agent $Agent --yes
    } finally {
        Pop-Location
    }
    Write-Host ""
}

Write-Host "✓  全部完成（$($Projects.Count) 个项目，$($Skills.Count) 个 skill）"