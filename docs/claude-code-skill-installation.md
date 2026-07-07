# Claude Code Skill 安装指南

> 本文档汇总 Claude Code Skill 的几种主流安装方式、相关管理工具的差异，以及如何获取公开 / 私有 skill 仓库。

---

## 目录

1. [安装方式总览](#安装方式总览)
2. [方法一：使用 Skill 管理工具（推荐）](#方法一使用-skill-管理工具推荐)
   - [skillslm](#skillslm)
   - [skillhubs](#skillhubs)
   - [skills（社区套装）](#skills社区套装)
3. [方法二：手动安装](#方法二手动安装)
4. [核心要点](#核心要点)
5. [工具对比：仓库来源](#工具对比仓库来源)
6. [skillhubs 的仓库来源详解](#skillhubs-的仓库来源详解)
7. [公开 Skill 仓库推荐](#公开-skill-仓库推荐)

---

## 安装方式总览

Claude Code Skill 的安装主要有 **手动安装** 和 **使用管理工具** 两种方式。**推荐用管理工具**，更省心：

| 维度 | 管理工具 | 手动安装 |
|---|---|---|
| 上手成本 | 一行命令 | 需要懂目录结构和 YAML frontmatter |
| 来源管理 | 自动从 GitHub / 私有仓库拉取 | 自己下载 / git clone |
| 版本管理 | 工具内置 update 命令 | 自己 git pull |
| 适用场景 | 大多数人 | 自定义 / 离线 / 内网部署 |

---

## 方法一：使用 Skill 管理工具（推荐）

### skillslm

功能最全面的管理工具，支持多种 AI 编程助手（不只是 Claude Code）。

```bash
# 交互式安装（推荐，会列出可选项）
npx skillslm install anthropics/skills

# 直接安装指定 Skill 到 Claude Code
npx skillslm install anthropics/skills --skill pdf --agent claude-code --yes
```

支持两种作用域：

- **项目级**（默认）：`./.claude/skills/<skill-name>/`，仅当前项目可用
- **全局**（加 `--global`）：`~/.claude/skills/<skill-name>/`，所有项目可用

```bash
# 项目级
npx skillslm install UryWu/urywu-skills --skill playwright-cli --agent claude-code --yes

# 全局
npx skillslm install UryWu/urywu-skills --skill playwright-cli --agent claude-code --global --yes
```

### skillhubs

适合企业内部管理 Skill，命令也很简单。

```bash
# 安装
npm install -g skillhubs

# 搜索并安装 Skill
skillhubs search <关键词>
skillhubs add <Skill名称>
```

> skillhubs 不从公共互联网的中央仓库搜索，而是依赖本地配置的**私有源**（企业内网 / 本地文件系统）——详见 [skillhubs 的仓库来源详解](#skillhubs-的仓库来源详解)。

### skills（社区套装）

社区里有些好用的 Skill 套装，能用一行命令装完。比如 Matt Pocock 的这套：

```bash
npx skills@latest add mattpocock/skills
```

安装后可能需要执行初始化命令（如 `/setup-matt-pocock-skills`）。

---

## 方法二：手动安装

如果你想自己写 Skill 或者安装一个从网上下载的，直接放到固定目录就行。

### 步骤 1：创建目录

在 Claude Code 存放 Skill 的文件夹里创建一个子目录：

- **全局路径**（推荐）：`~/.claude/skills/你的skill名字/`
- **项目级路径**：`./.claude/skills/你的skill名字/`

### 步骤 2：创建 `SKILL.md` 文件

在上面的目录里新建 `SKILL.md`，内容分两部分：**YAML 头信息** + **Markdown 正文**。

### 步骤 3：编写 Skill 内容

```markdown
---
name: commit
description: 根据暂存的变更生成commit message并提交
---

根据当前staged changes生成commit message并提交：

1. 执行 `git diff --cached` 看改了什么
2. 生成commit message，格式：`type(scope): description`
3. 执行 `git commit -m "message"`

如果没有staged内容，提示用户先 `git add`。
```

在 Claude Code 里输入 `/commit` 就能用了。

---

## 核心要点

- **全局 vs 项目级**：
  - `~/.claude/skills/` — 全局（所有项目可用，个人工具链首选）
  - `./.claude/skills/` — 项目级（仅当前项目，跟项目走的配置首选）
- **Skill 结构**：每个 Skill 就是一个包含 `SKILL.md` 文件的文件夹
  - YAML 头里的 `name` 是调用指令（用户用 `/name` 触发）
  - YAML 头里的 `description` 帮助 Claude **自动**识别场景（无需手动触发）
- **脚本支持**：skill 内部可携带 `scripts/`、`references/` 等附属文件

---

## 工具对比：仓库来源

| 工具 | 仓库来源 | 适合场景 |
|---|---|---|
| **skillhubs** | 本地 + 私有仓库（企业内网 / GitLab / 自建） | 团队内部共享，不对外 |
| **skillslm** | GitHub 公开仓库（`anthropics/skills` 等） | 跨项目复用、找现成的 |
| **skills**（Matt Pocock 版） | GitHub（特定作者的 skill 集合） | 跟某个作者的实践 |
| **官方 Claude Code** | 本地 `~/.claude/skills/` | 完全本地，无中央仓库 |
| **手动安装** | 任意来源（GitHub / 下载 / 自写） | 离线 / 自定义 / 内部测试 |

---

## skillhubs 的仓库来源详解

skillhubs 是一个**企业级 / 团队级**的 Skill 管理工具。它的设计理念是：**不依赖公共互联网的中央仓库**，而是让你自己配置 Skill 源。

### 默认来源

- **本地文件系统**：扫描 `~/.claude/skills/` 或项目目录下的 Skill
- **企业内网 / 私有 Git 仓库**：支持配置内部的 Skill 源（公司 GitLab、自建服务器等）

### 配置方式

通过配置文件指定 Skill 的来源：

```bash
# 查看当前配置的仓库源
skillhubs config list

# 添加一个私有的 Skill 仓库源
skillhubs config add source https://your-company-git.com/skills-repo.git
```

### 核心区别

| 维度 | skillhubs | skillslm |
|---|---|---|
| 仓库类型 | 私有（企业内） | 公开（GitHub） |
| 中央仓库 | ❌ 无 | ✅ `anthropics/skills` |
| 上手成本 | 需先配置源 | 装好就能用 |
| 适用人群 | 企业团队 | 个人 / 开源爱好者 |

> 💡 **结论**：如果你想要开箱即用的公开 Skill，推荐用 skillslm 或直接去 GitHub 找现成的 Skill 仓库手动安装；skillhubs 适合有内部 Skill 源、要统一管控的企业场景。

---

## 公开 Skill 仓库推荐

### 1. 用 skillslm 一键装官方源

```bash
npx skillslm install anthropics/skills
```

[`anthropics/skills`](https://github.com/anthropics/skills) 是 Anthropic 官方维护的 skill 集合（17 个），含 PDF / DOCX / PPTX / XLSX、frontend-design、mcp-builder、skill-creator 等。

### 2. 直接去 GitHub 找

搜索 `claude-code-skills` 或 `claude-skills`，找到后手动下载到 `~/.claude/skills/` 或 `./.claude/skills/`。

### 3. 官方 Skill 示例

- <https://github.com/anthropics/skills> — Anthropic 官方提供的示例集
- <https://github.com/UryWu/urywu-skills> — 本仓库（UryWu 个人 skill 集合）

### 4. Matt Pocock 等社区作者

```bash
npx skills@latest add mattpocock/skills
```

---

## 总结

| 你的需求 | 推荐工具 |
|---|---|
| 找一个能用的 skill 装上就跑 | **skillslm** |
| 企业内部统一管控 skill | **skillhubs** |
| 跟某个作者的实践 | **skills + 作者仓库** |
| 完全自写 / 离线 | **手动安装** |
| Skill 跨所有项目共享 | **全局安装**（任何工具 + `--global`） |
| Skill 只跟某个项目走 | **项目级安装**（任何工具默认即可） |

---

> 本文档由社区公开内容整理，写于 2026-07-07。工具版本会演进，命令细节请以最新源码为准。