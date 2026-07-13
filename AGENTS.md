# Agent 规范 — 给 AI 编码代理的协作约定

> 本文档定义 AI 编码代理（Claude Code、Cursor、Codex 等）在本仓库工作时必须遵守的约定。
> 人类协作者可跳过，但提交时请确保符合下文「Commit 注释规范」一节。

---

## 仓库定位

**UryWu Skills** 是一个 Claude Code skill 集中托管仓库（GitHub: `UryWu/urywu-skills`）。

- 每个 skill 是 `skills/<name>/` 下一个自包含子目录，含 `SKILL.md`（YAML frontmatter + Markdown 正文）和可选附属文件
- 其他项目通过 `npx skillslm install UryWu/urywu-skills --skill <name> --agent claude-code --yes` 一键安装
- layout 对齐 [`anthropics/skills`](https://github.com/anthropics/skills)

**当前托管 skill**：
- `fastapi-vue-version-bump` — 双组件（Python backend + Node frontend）版本号统一升降
- `fastapi-vue-docker-compose-deploy-strategy` — 通用 Dockerfile COPY + bind-mount 决策矩阵（rebuild vs start），含跨栈适配
- `fastapi-vue-docker-compose-deploy-strategy-simcard` — **项目特化备份**：上述通用版的 simcard 项目快照（含具体脚本实现）
- `playwright-cli` — 浏览器自动化

---

## 目录约定

```
urywu-skills/
├── AGENTS.md                       ← 本文件
├── README.md                       ← 面向人类用户的入口文档
├── .gitignore                      ← 忽略 .claude/（runtime）、plans/（本地草稿）
├── docs/                           ← 补充文档（如安装指南）
├── scripts/                        ← 仓库自身的运维脚本（不是 skill 的一部分）
│   ├── install-skills-to-projects.{sh,ps1}
│   ├── switch-to-global-install.{sh,ps1}
│   └── ...
└── skills/
    └── <skill-name>/
        ├── SKILL.md                ← 必须：YAML frontmatter（name + description）+ Markdown 正文
        ├── scripts/                ← 可选：skill 自带的脚本
        ├── references/             ← 可选：skill 引用文档
        └── test-*.{sh,ps1}         ← 可选：skill 自带回归测试
```

**关键约束**：
- `skills/<name>/SKILL.md` 的 frontmatter `name` 字段必须与目录名一致（kebab-case）
- `skills/<name>/` 内部文件不依赖任何父目录上下文（独立单元）
- 任何脚本无硬编码绝对路径（跨项目可移植）

---

## Commit 注释规范

**强制使用中文**。这是仓库的硬性约定。

### 格式

```
<类型>: <一句话中文描述>

<可选：详细说明（中文）>
```

### 类型（type）

沿用 Conventional Commits 的英文动词前缀，但 `:` 后面用中文：

| 类型 | 中文释义 | 适用场景 |
|---|---|---|
| `feat` | 新增 | 加新 skill、新脚本、新文档章节 |
| `fix` | 修复 | bug fix、误删恢复、占位符替换等 |
| `docs` | 文档 | 仅改 README / docs / SKILL.md 正文（不改代码） |
| `refactor` | 重构 | 不改外部行为的代码结构调整 |
| `chore` | 杂项 | 改 .gitignore、build 配置、注释等 |
| `test` | 测试 | 加/改回归测试 |
| `perf` | 性能 | 性能优化 |
| `style` | 格式 | 纯格式调整（空格、换行、引号等） |

### 示例

```
feat: 新增 fastapi-vue-docker-compose-deploy-strategy skill

新增 decision-matrix 驱动的 Docker Compose 部署策略 skill，
避免 5-47 min 无谓 rebuild。
```

```
fix(skill): bump_version 的 sed 锚定到 version 行，防止误改依赖版本号
```

```
docs: README 增加 skillslm --global 与项目级安装的对比说明
```

### 严禁

- ❌ 英文 commit 注释（即使是单词如 `feat: init`）
- ❌ 中文 + 英文混用（如 `feat: 新增 skill (add playwright-cli)`）
- ❌ 没有 type 前缀（`新增 skill` / `update README`）
- ❌ 一句话长 description（`feat: 这个 commit 主要做了一件事就是把原来写错的脚本名改回原来的正确写法`）

---

## 发布 / Tag 规范（SemVer）

| Tag 格式 | 适用变更 |
|---|---|
| `v1.0.0` | 首发 / API 锁定（v0.x → v1.x 是"稳定承诺"）|
| `v1.0.1` | patch：仅 bug 修复、向后兼容 |
| `v1.1.0` | minor：新增 skill、新增脚本（向后兼容）|
| `v2.0.0` | major：skill 接口破坏、脚本接口破坏、ALL_SKILLS 默认值语义变化 |

**Tag 注释必须中文**：
```
git tag -a v1.1.0 -m "v1.1.0 — 新增 fastapi-vue-docker-compose-deploy-strategy"
```

---

## 改动脚本时的红线

### 1. bump_version 的 mode 系统（高危）

修改 `skills/fastapi-vue-version-bump/scripts/bump_version.{sh,ps1}` 中的 `patch_file()` / `Update-VersionInFile()` 函数时：

- ❌ **绝不能** 恢复"裸 `s/OLD/NEW/g` 全文替换" — 这会把 `langchain>=0.4.0` 改成 `langchain>=0.4.1`
- ✅ 必须保持 4 个 mode 各自的锚定 regex：`toml` / `python` / `plain` / `json`
- ✅ 修改后必须跑 `scripts/test-patch-file.{sh,ps1}`：bash 13/13 + PowerShell 13/13 必须全绿

### 2. 全局 vs 项目级安装

修改 `scripts/install-skills-to-projects.*` 或 `scripts/switch-to-global-install.*` 时：

- ❌ **绝不能** 把 `npx -y` 改成 `npx`（前者是无人值守所必需）
- ❌ **绝不能** 假设 `cwd/.skills/` 是有效输出（见下文 skillslm bug）

### 3. skillslm v2.0.0 已知 bug

| 命令 | 期望行为 | 实际行为 | 正确绕路 |
|---|---|---|---|
| `npx skillslm update <url> --global` | 刷新 `~/.claude/skills/<agent>/` | 写到 `cwd/.skills/`（**全局不更新**）| 用 `npx skillslm install ... --global --yes` 替代 |

修脚本时不要相信 `update --global` 的行为。

---

## 添加新 skill 的流程

1. **在 `skills/<name>/` 建子目录**，含 `SKILL.md`（必须）
2. **更新 `README.md`**「当前托管的 skill」表格（必须）
3. **更新 `scripts/install-skills-to-projects.{sh,ps1}`** 的 `ALL_SKILLS` 数组（必须，默认安装）
   - 如新 skill 不希望默认装，加 `#` 注释掉（参考 `playwright-cli` 处理）
4. **可选**：在 `docs/` 加更详细的使用指南
5. **可选**：在 `skills/<name>/scripts/` 加自带脚本 + `test-*` 回归测试
6. **Commit + push**：中文 commit 注释，按 SemVer 该 bump minor 即 `v1.x.0`
7. **打 tag**：`git tag -a v1.x.0 -m "..."` 然后 `git push origin v1.x.0`

---

## 改动 PR / commit 前自检

- [ ] 是否所有 SKILL.md 的 `name` 字段都跟目录名一致？
- [ ] 是否所有 commit 注释都用中文 + Conventional Commits 前缀？
- [ ] 如果改了 `bump_version.*`，是否跑过 `test-patch-file.{sh,ps1}` 全绿？
- [ ] 如果改了 `scripts/install-*` 或 `switch-*`，是否手动 dry-run 过（至少 echo 阶段）？
- [ ] 是否更新了 README 的 skill 表格（如有新增）？
- [ ] 是否更新了 `ALL_SKILLS` 数组（如有新增）？
- [ ] 是否暴露了真实服务器 IP / 凭据 / 邮箱？如有，必须替换为占位符或 `.gitignore`。
- [ ] `.gitignore` 是否需要更新（如新增了临时目录 / runtime 文件）？

---

## 严禁

- ❌ 把服务器 IP、PAT、SSH key、邮箱等敏感信息 commit
- ❌ 把 `~/.claude/skills/<skill>/` 的本地改动直接复制过来 — 那是 runtime，从仓库 canonical 拉
- ❌ 跳过 `test-patch-file.*` 跑测试就 commit `bump_version.*` 改动
- ❌ 在 PR / commit 里用英文（即使其他协作者都用英文）

---

## 跨仓同步（源项目侧）

如果你是源项目（如 `data_sim_card_purchase_provide_data`）的 AI 代理，需要把 skill 改动同步回 `urywu-skills`：

```bash
# 1. 拉本仓库最新
cd G:/Projects/projects_ai_skills_plugins/urywu-skills
git pull origin main

# 2. 全局更新（用 install --global 绕路 update --global 的 bug）
rm -rf ~/.claude/skills/<skill-name>
npx -y skillslm install UryWu/urywu-skills --skill <skill-name> --agent claude-code --global --yes
```

反之，把本仓库的变更同步到源项目本地副本：
```bash
# 在源项目里
npx -y skillslm install UryWu/urywu-skills --skill <skill-name> --agent claude-code --yes
# install 会覆盖式刷新本地副本（fs.rmSync + copySkillDirectory）
```

---

## 反馈 / 改进

如发现本文档有遗漏 / 错误 / 可改进之处，请直接修改并提 PR。规范本身也是代码。