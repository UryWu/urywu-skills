# scripts/switch-to-global-install.ps1 — 把 skill 从项目级切到全局（PowerShell 版）
#
# Bash 等价版本：scripts/switch-to-global-install.sh
#
# 操作流程：
#   Step 1: 从默认 4 个项目里移除 skill 的项目级副本
#   Step 2: 用 --global 装一次到 ~/.claude/skills/
#
# Usage:
#   .\scripts\switch-to-global-install.ps1                                       # 切 fastapi-vue-version-bump
#   .\scripts\switch-to-global-install.ps1 playwright-cli                        # 切 playwright-cli
#   .\scripts\switch-to-global-install.ps1 fastapi-vue-version-bump playwright-cli   # 一次切多个
#
# 默认目标项目（要切的项目）：
#   G:\Projects\projects_ai\audio2text
#   G:\Projects\projects_ai\data_sim_card_purchase_provide_data
#   G:\Projects\projects_ai\openlink
#   G:\Projects\projects_ai_skills_plugins\urywu-skills
#
# 危险：此脚本会 Remove-Item -Recurse 项目里的 .claude\skills\<name>。运行前确认
# 你已经备份或者接受"用全局版覆盖"。

$ErrorActionPreference = "Stop"

$Repo = "UryWu/urywu-skills"
$Agent = "claude-code"

# 默认 skill
if ($args.Count -eq 0) {
    $Skills = @("fastapi-vue-version-bump")
} else {
    $Skills = $args
}

# 目标项目列表
$Projects = @(
    "G:\Projects\projects_ai\audio2text",
    "G:\Projects\projects_ai\data_sim_card_purchase_provide_data",
    "G:\Projects\projects_ai\openlink",
    "G:\Projects\projects_ai_skills_plugins\urywu-skills"
)

# Step 1: 移除项目级副本
Write-Host "=== Step 1: 移除项目级副本 ==="
foreach ($project in $Projects) {
    if (-not (Test-Path -LiteralPath $project -PathType Container)) {
        Write-Host "⚠  跳过（项目不存在）: $project"
        continue
    }
    foreach ($skill in $Skills) {
        $target = Join-Path $project ".claude\skills\$skill"
        if (Test-Path -LiteralPath $target -PathType Container) {
            Write-Host "  Remove-Item -Recurse $target"
            Remove-Item -LiteralPath $target -Recurse -Force
        } else {
            Write-Host "  - 不存在，跳过: $target"
        }
    }
}
Write-Host ""

# Step 2: 全局安装
Write-Host "=== Step 2: 全局安装 ==="
$skillArgs = @()
foreach ($s in $Skills) {
    $skillArgs += "--skill"
    $skillArgs += $s
}
Write-Host "   skills: $($Skills -join ', ')"
& npx -y skillslm install $Repo @skillArgs --agent $Agent --global --yes
Write-Host ""

Write-Host "✓ 完成（$($Skills.Count) 个 skill 已切到全局 ~/.claude/skills/）"
Write-Host ""
Write-Host "回退方案：如需回到项目级，运行："
Write-Host "  .\scripts\install-skills-to-projects.ps1 $($Skills -join ' ')"