---
name: fastapi-vue-version-bump
description: Bump version across the two versioned components of a typical FastAPI+Vue (or Python-backend + Node-frontend) project (backend / frontend; add a third in the bundled scripts to fit your project) by running scripts/bump_version.{sh,ps1}, regenerate lockfiles safely (uv lock / npm install — never sed them), update CHANGELOG.md in Keep-a-Changelog categories, and run the release commit/tag/push workflow. Ships pre-configured for Python+Vue projects; to swap toolchains (e.g. uv lock for cargo generate-lockfile), edit the bundled scripts. Use when the user says "升级版本" / "bump to vX.Y.Z" / "release vX.Y.Z" / "patch" / "minor" / "major", asks which SemVer bump to apply, reports a stale-version warning, asks about lockfile corruption (uv.lock / package-lock.json / Cargo.lock 404s), or is adding a new version-bearing file to the bump script.
---

# Version Bump (2-Component Project)

## Overview

A typical FastAPI+Vue (or other Python-backend + Node-frontend) project has **two versioned components** — a backend service and a frontend app. When a release happens, both components move together — but writing/sed-ing each version slot by hand reliably misses files.

This skill centralizes the bump in a single driver script that:
1. Reads each component's **source-of-truth** version file,
2. Computes the target version (literal `X.Y.Z` or `patch|minor|major` bump from current),
3. `sed` (or `.Replace` on PowerShell) updates every version-bearing file in each component,
4. regenerates lockfiles via the package manager's lock command (NEVER by sed),
5. verifies no stale version strings remain, and
6. prints a suggested commit/tag/push sequence.

> The bump driver intentionally does NOT do git operations (commit / tag / push stay manual) — auto-generated commit messages are almost never what you want, and tag subjects need real prose.

## Ships pre-configured for…

Out of the box, the bundled `scripts/bump_version.{sh,ps1}` are configured for **2 components** (Python backend + Vue 3 frontend):

| Component | Source of truth | Synced files (sed'd by driver) |
|---|---|---|
| `backend`   (Python/FastAPI) | `<project>/backend/pyproject.toml`            | `backend/VERSION`, `backend/app/main.py`, `backend/app/schemas/types.py`, `backend/app/api/endpoints/health.py` |
| `frontend`  (Vue 3)           | `<project>/frontend/package.json`             | — |

### Adding a third component (or adapting to a different stack)

To add a third component to this 2-comp skill (e.g. a browser extension, a CLI tool, a worker):

1. **Append an entry** in:
   - `COMPONENT_FILES[<name>]`, `COMPONENT_READ[<name>]`, `COMPONENT_SYNC[<name>]` arrays in `scripts/bump_version.sh`
   - `$Components[$name] = @{ ... }` block in `scripts/bump_version.ps1`
   - The `for comp in ...` and `foreach ($name in ...) { ... }` loops
   - The override-var / switch-case logic (param, OVERRIDE_BACKEND="", `case --<name>`, `'<name>' { $override = $<Name> }`)
2. **Add a `read_version_<name>()` function** (shell) / **a `Reader` scriptblock** (PowerShell) that prints the current version to stdout.
3. **Add a `sync_lock_<name>()` function** / **a `Sync` scriptblock** matching your toolchain.
4. **Bump the count checks**: `[[ ${#NEW_VERSIONS[@]} -eq 2 ]]` → 3 in shell, `$changedCount -eq 2` → 3 in PowerShell.
5. **Dry-run**: `./scripts/bump_version.sh patch` should print `already at X.Y.Z (skip)` for unchanged components.

To swap toolchains without adding components, edit just `sync_lock_backend` (`uv lock` → e.g. `cargo generate-lockfile`) and `sync_lock_frontend` (`npm install` → e.g. `yarn install --frozen-lockfile`).

## Bundled resources

This skill carries copies of three files for self-containment; **the project canonical copies are the single source of truth** — keep them in sync by running `<project>/scripts/sync_skill_copies.sh` after every edit. (That helper is not bundled; recreate it from the "Adding a new version-bearing file" pattern.)

- `scripts/bump_version.sh` — bundled bash bump driver. For execution, use the project copy at `<project>/scripts/bump_version.sh`; this copy is a reference snapshot.
- `scripts/bump_version.ps1` — bundled PowerShell bump driver. Same pattern, PS-cased param names (`-Backend` not `--backend`).

## When to invoke

Triggers that should pull this skill in:
- "升级版本到 vX.Y.Z", "bump to X.Y.Z", "release vX.Y.Z"
- "patch" / "minor" / "major" as a verb
- "为什么上次漏改了", "stale references" warning from the script
- "uv sync 报 404", "uv.lock 坏了" / "package-lock.json corrupted" / "Cargo.lock version drift" → root cause was a sed, this skill explains why
- adding a new file that carries `__version__`
- questions about whether this version should be patch / minor / major

## Decide the version type

Apply SemVer mentally BEFORE running the script:

| Change since last release | Bump type |
|---|---|
| Bug fix only, no new feature | `patch` (1.1.1 → 1.1.2) |
| New backward-compatible feature, no breaking change | `minor` (1.1.1 → 1.2.0) |
| Breaking change (API, config, removed feature) | `major` (1.1.1 → 2.0.0) |

A period of **all new features and zero bug fixes** correctly jumps 1.1.1 → 1.2.0 directly. Don't pad patch numbers.

Override individual components for hot-fixes:
```bash
# Linux/macOS / Git Bash (PowerShell: --backend → -Backend, etc.)
./scripts/bump_version.sh 1.2.0 --backend 1.1.5    # backend sticks; others → 1.2.0
./scripts/bump_version.sh patch --frontend minor   # backend +=patch, frontend +=minor
```

### Major bump (v1.x → v2.0.0): API 向下兼容**不是必须的**，恰恰是 v2.0.0 的正当理由

按 [SemVer](https://semver.org/) 规范，从 v1.2.1 → v2.0.0 这步跳跃**明确允许并宣告了不兼容的 API 修改**——"不需要做向下兼容"恰恰是 v2.0.0 存在的意义，不是需要担忧的问题。

#### SemVer 三档规则速查

| 变更性质 | bump 类型 | 示例 |
|---|---|---|
| 不向下兼容（重命名函数 / 修改参数签名 / 删除旧接口） | **主版本号** | 1.2.1 → **2.0.0** |
| 新增向下兼容的功能 | **次版本号** | 1.1.1 → 1.**2**.0 |
| 向下兼容的 bug 修复 | **修订号** | 1.1.**1** → 1.1.**2** |

v1.2.1 → v2.0.0 在语义上等价于：
- **当前状态 (v1.2.1)**：稳定的 v1 版本，API 已冻结
- **未来版本 (v2.0.0)**：包含破坏性变更，不再与 v1 完全兼容

> 主版本号的存在本身就是为了让使用者**仅凭版本号**就知道升级的风险等级——v2.0.0 不是"做错了要补救"，而是"明确告知：这次会 break"。

#### 升级到 v2.0.0 的最佳实践

虽然规则上 v2.0.0 不需要兼容 v1.x，但要让使用者能平稳迁移：

1. **提前弃用（Deprecation cycle）**
   - 在 v1.x 生命周期里通过一个**次版本**（如 v1.3.0）把计划移除/修改的 API 标记为 `@Deprecated`，告知新接口路径
   - 不要在 v2.0.0 静默删 API——给使用者一个缓冲期
2. **同步 CHANGELOG**（本 skill 上方「Update CHANGELOG.md」章节强制要求）
   - 破坏性变更放进 Keep-a-Changelog 的 `### Changed` / `### Removed` 分类
   - 主版本升级要**单独一节** `## [2.0.0] - YYYY-MM-DD`，把所有破坏点列清楚
3. **写迁移指南（Migration Guide）**
   - 在 `## [2.0.0]` 段落或独立 `docs/MIGRATION-v2.md` 里给"v1 → v2"的具体步骤
   - 重点写：哪些 import 路径变了、哪些参数签名变了、哪些功能被整体替换
4. **版本号重置**
   - 主版本号从 v1.2.1 → v2.0.0 时，**次版本号和修订号必须重置为 0**
   - 本 skill 的 `bump_version.{sh,ps1}` 在处理 `major` 时已经做这件事（`MAJOR+1`，MINOR/PATCH=0）—— 见脚本中 `bump_version` 函数的 `major) echo "$((MAJOR + 1)).0.0"` 分支
5. **本 skill 自身升级 v2.0.0**
   - 跑 `./scripts/bump_version.sh 2.0.0`（或 `major`）一次到位
   - 别忘了手动把"破坏性变更清单"作为 `### Changed` / `### Removed` 条目写进 CHANGELOG，再 commit + tag + push

> 💡 **结论**：可以放心发布 v2.0.0。"不需要向下兼容"是 v2.0.0 的正当理由，不是需要担忧的事。只需要通过弃用周期 + CHANGELOG + 迁移指南让使用者能平滑过渡。

## Run the bump

From repo root:

```bash
# Linux/macOS / Git Bash
./scripts/bump_version.sh 1.2.0
./scripts/bump_version.sh patch

# Windows PowerShell (capitalized param names per PS convention)
.\scripts\bump_version.ps1 1.2.0
.\scripts\bump_version.ps1 patch -Frontend minor
```

The script will, in order:
1. Read each component's current version from its source-of-truth file.
2. Compute target per component (literal `X.Y.Z` or `patch|minor|major` from current).
3. `sed` (or `.Replace`) the version-bearing files — NOT lockfiles (see Pitfalls).
4. Run the configured package-manager lock command per moved component (e.g. `uv lock` / `npm install`) to regenerate lockfiles.
5. Grep for stale references; exit 1 if any non-lockfile file still contains the old version.
6. Print `git diff --stat` (version files only) and a suggested commit message.

## ⚠️ Update CHANGELOG.md (do NOT skip)

> This is the most commonly forgotten step in a release. After the bump script succeeds but **before** committing, write the new version's section in the project's changelog file (commonly `CHANGELOG.md`).

Required behavior, matching the existing layout in your changelog:

1. Replace the `## [Unreleased]` heading (and its empty body) with a new `## [X.Y.Z] - YYYY-MM-DD` heading. Leave a fresh empty `## [Unreleased]` above for the next cycle.
2. Move (don't duplicate) any leftover `[Unreleased]` content into the new dated section.
3. Categorize fresh notes under Keep-a-Changelog headings (`### Added` / `### Fixed` / `### Changed` / `### Removed`, plus `### Security` only when relevant).
4. Bullet style — each line starts `- **bold heading**:` followed by the change, often referencing the file path in backticks. Indent continuation lines by two spaces.
5. One bullet per file-change is the norm; do not collapse multi-file features into a single mega-bullet.
6. Order within each section: most user-visible first; critical bugs and breaking changes near the top.

When uncertain about what landed since the last tag, cross-check with:
```bash
git log --oneline vX.Y.Z~..vX.Y.Z
# or, for a wider net:
git diff vX.Y.Z~ -- ':!CHANGELOG.md' ':!*.lock' ':!*package-lock.json' | head
```

For a **pure patch** (single bug fix), one `### Fixed` bullet is enough.

After editing, eyeball `git diff <changelog-file>` to confirm:
- Date is today's local date in `YYYY-MM-DD`.
- Heading is exactly `## [X.Y.Z] - YYYY-MM-DD` (square brackets, single space, hyphen, single space, date).
- No leftover populated `## [Unreleased]` block.

## Release: commit, tag, push

After both the script edits AND the changelog are staged:

```bash
git status                                 # bump files + lockfiles + CHANGELOG.md
git diff --stat                            # (script already printed stat for version files only)
git diff <changelog-file>                  # eyeball before committing

git add -A
git commit -m "chore: 升级版本到 v1.2.0"
# If only some components moved, the script's suggested message looks like:
#   "chore: 升级版本 (<comp1>:1.1.5→1.1.6) (<comp2>:1.1.1→1.2.0)"

git tag -a v1.2.0 -m "v1.2.0 — <one-line description of the headline change>"
git push origin main
git push origin v1.2.0                     # always push tag and main in the same batch
```

## Publish: GitHub Release

After `git push origin main && git push origin vX.Y.Z` succeed, before declaring done, **publish the GitHub Release page** so the new version's CHANGELOG section is visible to consumers browsing the repo.

### Step 0: Ask user for PAT configuration

Before any token discovery, **always ask the user** which option applies — do not assume. Use `AskUserQuestion`:

> **Question**: "How is your GitHub PAT configured for publishing releases?"
>
> **Options**:
> 1. **Stored in `~/.claude.json`** — search the file for any key containing a GitHub PAT and report the matches (let user pick which one to use).
> 2. **In environment variable** — ask the user for the variable name (e.g. `GH_TOKEN`) holding the PAT.
> 3. **User pastes it in chat** — user provides the PAT directly in the response (will be lost after session ends — use option 1 or 2 for persistence).
> 4. **Not configured** — skip publishing; tell the user to publish via the GitHub web UI manually.

Stop here if option 4 is chosen — the rest of this section does not apply.

### Step 1: Discover the PAT

For **option 1** (`~/.claude.json`):

- Recursively scan the JSON tree for any string matching `github_pat_[A-Za-z0-9_]+`.
- For each match, report the **full JSON path** to the key (e.g. `projects['G:/foo'].mcpServers.github.headers.Authorization`).
- **Critical extraction gotcha**: PATs are often embedded inside other JSON values (e.g. an `mcpServers.github.command` string that wraps a JSON config). Naive split by space will pick up trailing JSON artifacts like `}}'` and break auth. Always extract with a character-class regex:
  ```python
  import re
  m = re.search(r'(github_pat_[A-Za-z0-9_]+)', value)
  token = m.group(1) if m else None
  ```
  Do NOT use `value.split(' ', 1)[1]` or `\S+` — both leak surrounding punctuation.

For **option 2** (env var): `os.environ[<user_provided_name>]`. If the variable is empty/unset, stop and report.

### Step 2: Validate the token

Before publishing, run a cheap auth check:

```python
import urllib.request
req = urllib.request.Request(
    'https://api.github.com/user',
    headers={'Authorization': f'Bearer {token}', 'Accept': 'application/vnd.github+json'},
)
with urllib.request.urlopen(req) as resp:
    body = json.loads(resp.read())
    print('login:', body.get('login'))
```

If HTTP **401** (`Bad credentials`), the token is **expired or revoked** — stop and tell the user to refresh the PAT. Do NOT retry.

If HTTP **403** with "API rate limit exceeded" — wait a few minutes (unauthenticated requests are limited to 60/hour; authenticated to 5000/hour) and retry.

### Step 3: Publish via API (preferred) or `gh` CLI

**Preferred path: Python `urllib.request`** — avoids shell-escape issues with multilingual CHANGELOG content. `curl --data-binary` on Windows Git Bash can corrupt JSON containing `&&`, `<`, Chinese characters, etc. `gh release create --notes-file` on Windows has `/tmp` path issues (use repo-local paths instead).

```python
import json, re, urllib.request

# 1) Extract new version's CHANGELOG section
#    (between "## [X.Y.Z] - DATE" and the next "## [" heading)
changelog = open('CHANGELOG.md', encoding='utf-8').read()
m = re.search(
    rf'## \[{version}\][^\n]*\n(.*?)(?=\n## \[|\Z)',
    changelog,
    re.DOTALL,
)
notes = m.group(1).strip() if m else ''

# 2) Build payload
payload = json.dumps({
    'tag_name': f'v{version}',
    'target_commitish': 'main',
    'name': f'v{version}',
    'body': notes,
    'draft': False,
    'prerelease': False,
}, ensure_ascii=False).encode('utf-8')

# 3) POST
req = urllib.request.Request(
    f'https://api.github.com/repos/{owner}/{repo}/releases',
    data=payload,
    method='POST',
    headers={
        'Authorization': f'Bearer {token}',
        'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json; charset=utf-8',
        'X-GitHub-Api-Version': '2022-11-28',
    },
)
try:
    with urllib.request.urlopen(req) as resp:
        body = json.loads(resp.read())
        print(f'HTTP {resp.status}')
        print(f'html_url: {body.get("html_url")}')
        print(f'tag_name: {body.get("tag_name")}')
except urllib.error.HTTPError as e:
    print(f'HTTP {e.code} {e.reason}')
    print(e.read().decode('utf-8'))
```

**Expected responses**:
- **HTTP 201** — release created. Print the `html_url` so the user can click through.
- **HTTP 400** (`Problems parsing JSON`) — payload corrupted, usually from shell escaping. Switch from `curl` to Python `urllib.request` (don't retry with curl).
- **HTTP 401** — token rejected at publish time even though `/user` worked. Usually means token lacks `Contents: write` scope. Stop and tell the user.

### Step 4: Clean up

If you wrote notes to a temp file (e.g. `.release-notes.md` in repo root, or any file under `/tmp`), `rm` it after a successful 201 response. Do **NOT** commit it — it duplicates CHANGELOG content.

**Alternative — `gh` CLI**: if the user prefers the official CLI and the path/encoding issues are not a concern:

```bash
gh release create vX.Y.Z \
  --repo <owner>/<repo> \
  --title "vX.Y.Z" \
  --notes-file <path-to-notes>   # use repo-local path, NOT /tmp
gh release view vX.Y.Z --repo <owner>/<repo>  # verify
```

But the Python API path is preferred for multilingual CHANGELOG content.

## Pitfalls

- **Lockfile corruption** — never `sed s/1.1.1/1.2.0/g` over a lockfile (`uv.lock`, `package-lock.json`, `Cargo.lock`, etc.). It will turn a transitive dep's version into a nonexistent one and the next install command will 404. Always let the package manager regenerate (`uv lock`, `npm install`, `cargo generate-lockfile`, etc.).
- **Missed file** — if you add a file carrying the version string, the script's grep verify will fail with "stale references". Update both the shell script's `COMPONENT_FILES[<component>]` and the PowerShell script's `Files = @(...)` array, then run `<project>/scripts/sync_skill_copies.sh` (if you have one) to push into the skill's bundled copies.
- **Tag pushed later than main** — `git push origin main` without `git push origin vX.Y.Z` makes installs of the new tag fail. Always push both in the same batch.
- **Bumping without CHANGELOG** — the GitHub Release body comes out empty or stale; downstream consumers won't know what changed.
- **Pre-release versions** — the bundled script regex `^\d+\.\d+\.\d+$` rejects `1.2.0-beta.1`. If you need pre-release tags, relax the regex (in both shell and PowerShell scripts) or accept that this skill won't auto-handle it.

## Adding a new version-bearing file

> Always edit the **project canonical** scripts first, then run `<project>/scripts/sync_skill_copies.sh` (if you have one) to push project → skill copies in one shot. Bundled copies are reference snapshots; project canonical wins.

1. Pick the component (one of your project's versioned components).
2. In `<project>/scripts/bump_version.sh` (canonical), append `path|plain` or `path|json` on a new line in `COMPONENT_FILES[<component>]`.
3. Mirror in `<project>/scripts/bump_version.ps1` (canonical): add `@{ Path = "..."; Mode = 'plain' }` or `'json'` to the `Files = @(...)` array.
4. Run `./scripts/sync_skill_copies.sh` to push both edits into the skill's bundled copies.
5. Smoke test: `./scripts/bump_version.sh patch` from project root should print `already at X.Y.Z (skip)` for unchanged components and exit 0.
6. Real test: edit one existing file's version by hand, then re-run `./scripts/bump_version.sh patch` — confirm the new file is also touched.

## Reference

This skill ships in `scripts/bump_version.{sh,ps1}` (canonical) — edit those project copies, then run `<project>/scripts/sync_skill_copies.sh` to push into these bundled snapshots.
