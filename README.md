# UryWu Skills

UryWu 个人 Claude Code skill 集中托管点。

通过 [`skillslm`](https://www.npmjs.com/package/skillslm) 一键安装到任意项目的 `.claude/skills/<skill-name>/` 目录，免去手动复制。

---

## 当前托管的 skill

| Skill | 说明 | 适用场景 |
|---|---|---|
| [`fastapi-vue-version-bump`](skills/fastapi-vue-version-bump/SKILL.md) | 双组件版本号统一升降（后端 + 前端），自动重生成 lockfile、维护 CHANGELOG | FastAPI+Vue、Python+Node 等双组件项目发版 |
| [`playwright-cli`](skills/playwright-cli/SKILL.md) | 浏览器自动化、网页测试、Playwright 调试 | Web 端到端调试、UI 自动化 |

---

## 安装

### 安装全部 skill

```bash
npx skillslm install UryWu/urywu-skills --agent claude-code --yes
```

### 安装单个 skill

```bash
npx skillslm install UryWu/urywu-skills --skill fastapi-vue-version-bump --agent claude-code --yes
npx skillslm install UryWu/urywu-skills --skill playwright-cli --agent claude-code --yes
```

skill 默认安装到 `./.claude/skills/<skill-name>/`，与本机现有布局一致。

### 安装位置：全局 vs 项目级

`--global` / `-g` 控制安装作用域（v2.0.0 源码 `getInstallPath`）：

| 模式 | 路径（Claude Code agent） | 适用场景 |
|---|---|---|
| **项目级**（默认，无 `--global`） | `./.claude/skills/<skill-name>/`（跟随 `cwd`） | skill 只跟当前项目走；不同项目可有不同版本 |
| **全局**（加 `--global`） | `~/.claude/skills/<skill-name>/` | 所有项目共享同一份 skill；个人工具链类首选 |

```bash
# 项目级（默认）— 只对当前项目生效
npx skillslm install UryWu/urywu-skills --skill playwright-cli --agent claude-code --yes

# 全局 — 所有项目生效
npx skillslm install UryWu/urywu-skills --skill playwright-cli --agent claude-code --global --yes
```

**何时选哪个**：
- `playwright-cli`（通用浏览器工具）→ 全局（任何项目都可能用到）
- `fastapi-vue-version-bump`（2-component 项目模板）→ 视情况：如果是个人发版习惯统一 → 全局；如果是多套布局并存 → 项目级

**不同 agent 的全局路径不同**（`agents.js` 表）：

| Agent | 全局路径 |
|---|---|
| `claude-code` | `~/.claude/skills` |
| `cursor` | `~/.cursor/skills` |
| `codex` | `~/.codex/skills` |
| `opencode` | `~/.config/opencode/skill` |
| `amp` | `~/.config/agents/skills` |
| `kilo` | `~/.kilocode/skills` |
| `roo` | `~/.roo/skills` |
| `goose` | `~/.config/goose/skills` |
| `antigravity` | `~/.gemini/antigravity/skills` |

`--agent` 是 variadic，可同时多 agent 安装：`--agent claude-code cursor`。

### 批量安装到多个项目

如果你要在多个项目里一次装好（避免手动一个个跑），仓库自带 `scripts/install-skills-to-projects.{sh,ps1}`：

```bash
# Git Bash / WSL
./scripts/install-skills-to-projects.sh                                # 装 ALL_SKILLS 列表里的全部
./scripts/install-skills-to-projects.sh playwright-cli                 # 只装一个
./scripts/install-skills-to-projects.sh a b c                         # 一次装多个

# PowerShell（参数完全相同）
.\scripts\install-skills-to-projects.ps1
```

默认目标项目写死在脚本顶部（`PROJECTS` 数组），按需修改。脚本自带幂等（可重复运行）+ `npx -y`（无人值守）。`ALL_SKILLS` 数组是默认安装列表，新加 skill 后在那里同步登记即可。

---

## 更新

> **注意**：`skillslm install` 在目标已存在时会**覆盖**（源码 `fs.rmSync` 后 `copySkillDirectory`，带 warning 日志"将覆盖"）；`skillslm update` 也覆盖，但 update **不会记录来源**——必须传完整的 GitHub URL。

```bash
npx skillslm update https://github.com/UryWu/urywu-skills/tree/main/skills/fastapi-vue-version-bump
npx skillslm update https://github.com/UryWu/urywu-skills/tree/main/skills/playwright-cli

# 全局安装的 skill 更新时要带 --global
npx skillslm update https://github.com/UryWu/urywu-skills/tree/main/skills/playwright-cli --global
```

或者直接重新安装（install 也会覆盖，所以"删+装"和"update"效果相近，但 install 是全量复制）：

```bash
rm -rf .claude/skills/fastapi-vue-version-bump
npx skillslm install UryWu/urywu-skills --skill fastapi-vue-version-bump --agent claude-code --yes
```

---

## 卸载

> ⚠️ **skillslm v2.0.0 没有 `uninstall` 子命令**（已对照源码确认：只有 `install` / `list` / `update`）。卸载就是直接删目录——skillslm 不维护安装注册表，删除即彻底卸载。

### 卸载单个 skill

skill 默认安装到 `./.claude/skills/<skill-name>/`，直接 `rm -rf` 即可：

```bash
# Claude Code agent（最常见）
rm -rf .claude/skills/fastapi-vue-version-bump
rm -rf .claude/skills/playwright-cli
```

如果你之前用了 `--global` 装到全局目录，则删对应路径：

```bash
rm -rf ~/.claude/skills/fastapi-vue-version-bump
```

### 重置后重装（"伪更新"）

因为 `skillslm install` 在目标已存在时会**覆盖**（`fs.rmSync` 后再 `copySkillDirectory`），所以可以靠"先删再装"做一次干净重装：

```bash
rm -rf .claude/skills/fastapi-vue-version-bump
npx skillslm install UryWu/urywu-skills --skill fastapi-vue-version-bump --agent claude-code --yes
```

> 这比 `skillslm update <full-url>` 更稳：update 走的是浅层文件同步，可能漏掉你新加的 `references/` 或 `scripts/` 子文件；"删+装"是全量复制。

---

## 项目级 → 全局迁移

想把某个 skill 从项目级（`./.claude/skills/`）切到全局（`~/.claude/skills/`，所有项目共享）？用仓库自带的 `scripts/switch-to-global-install.{sh,ps1}`：

```bash
# Git Bash / WSL
./scripts/switch-to-global-install.sh                              # 切 fastapi-vue-version-bump
./scripts/switch-to-global-install.sh playwright-cli               # 切 playwright-cli
./scripts/switch-to-global-install.sh a b c                       # 一次切多个

# PowerShell（参数完全相同）
.\scripts\switch-to-global-install.ps1
```

脚本做两件事：

1. **Step 1** — 从默认 4 个项目里 `rm -rf .claude/skills/<skill>`
2. **Step 2** — `npx skillslm install ... --global --yes` 装到 `~/.claude/skills/`

⚠️ **破坏性操作**：会删除项目里的副本。运行前确认或先备份。回退：再跑 `./scripts/install-skills-to-projects.sh` 装回项目级。

何时切换：
- 通用工具（如 `playwright-cli`）→ 全局更省心（一次装到处可用）
- 项目特定配置 → 保留项目级（避免影响其他项目）

详细对比见上方「安装位置：全局 vs 项目级」。

---

## 布局约定

仓库根下 `skills/` 子目录对齐 [`anthropics/skills`](https://github.com/anthropics/skills) 布局：

```
urywu-skills/
├── README.md
├── .gitignore
├── docs/
│   └── claude-code-skill-installation.md
├── scripts/
│   ├── install-skills-to-projects.sh
│   ├── install-skills-to-projects.ps1
│   ├── switch-to-global-install.sh
│   └── switch-to-global-install.ps1
└── skills/
    ├── fastapi-vue-version-bump/
    │   ├── SKILL.md
    │   └── scripts/
    │       ├── bump_version.sh
    │       └── bump_version.ps1
    └── playwright-cli/
        ├── SKILL.md
        └── references/
            └── ...
```

- `skills/<name>/` — 对齐 anthropics/skills 布局，每个 skill 自包含 `SKILL.md` + 附属文件
- `scripts/` — 仓库自身的运维脚本（批量安装、全局迁移等），**不是** skill 本身的一部分
- `docs/` — 补充文档（如 Claude Code Skill 安装全解）

每个 skill 内部 `SKILL.md / scripts/ / references/` 布局原样保留。

---

## 添加新 skill

1. 在 `skills/<skill-name>/` 下新建子目录，包含 `SKILL.md`（必须有 YAML frontmatter：`name`、`description`）
2. skill 内部可携带 `scripts/`、`references/` 等附属文件
3. 在本 README 的「当前托管的 skill」表格里加一行
4. `git add` + `git commit` + `git push`

发布前自检：
- `SKILL.md` 顶部 frontmatter 合法（name kebab-case、description 一句话概括 + 触发场景）
- 脚本无硬编码绝对路径（跨项目可移植）
- 文件不依赖任何父目录上下文（独立单元）

---

## 更多公开 skill 仓库

如果你想要公开的 Skill 仓库，用 skillslm 搜索安装开源 Skill：

```bash
npx skillslm install anthropics/skills
```

[`anthropics/skills`](https://github.com/anthropics/skills) 是 Anthropic 官方维护的 skill 集合（skillslm 默认源），布局与本仓库完全一致（`skills/<name>/SKILL.md`），可直接通过 `owner/repo` shorthand 一键安装全部。可与本仓库的 skill 共存在 `.claude/skills/`，互不覆盖。

### 安装单个 skill（`--skill`）

不加 `--skill` 会装全仓库（17 个 skill，按需很多）。用 `--skill <name>` 只装要的：

```bash
npx skillslm install anthropics/skills --skill pdf --agent claude-code --yes
npx skillslm install anthropics/skills --skill xlsx --agent claude-code --yes
```

`--skill` 是 variadic，可一次装多个：

```bash
npx skillslm install anthropics/skills --skill pdf docx pptx xlsx --agent claude-code --yes
```

**当前 anthropics/skills 收录的 17 个 skill**：

| Skill | 用途 |
|---|---|
| `algorithmic-art` | 算法艺术（p5.js） |
| `brand-guidelines` | 品牌指南 |
| `canvas-design` | 画布设计 |
| `claude-api` | Claude API / Anthropic SDK 用法 |
| `doc-coauthoring` | 文档协作 |
| `docx` | Word 文档创建/编辑 |
| `frontend-design` | 前端设计 |
| `internal-comms` | 内部沟通 |
| `mcp-builder` | MCP server 构建 |
| `pdf` | PDF 文档创建/编辑 |
| `pptx` | PowerPoint 创建/编辑 |
| `skill-creator` | skill 创建模板 |
| `slack-gif-creator` | Slack GIF 创作 |
| `theme-factory` | 主题工厂 |
| `web-artifacts-builder` | Web artifacts 构建 |
| `webapp-testing` | Web 应用测试 |
| `xlsx` | Excel 表格创建/编辑 |

预查看某个 skill 是什么（在 `skills/<name>/SKILL.md` 里），可加 `--list` 列出仓库内全部 skill（不实际安装）：

```bash
npx skillslm install anthropics/skills --list
```

---

## 文档

补充文档（非 skill 本体）：

- [`docs/claude-code-skill-installation.md`](docs/claude-code-skill-installation.md) — Claude Code Skill 安装方式全解（手动 vs 工具、skillslm vs skillhubs vs skills、各 agent 全局路径、skillhubs 私有源机制详解、决策表）

---

## 协议

公开仓库，遵循 skillslm 公开协议。skill 一旦发布即可被任意项目 `install`。