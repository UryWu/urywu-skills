---
name: fastapi-vue-docker-compose-deploy-strategy
description: Generic decision matrix for FastAPI + Vue + Docker Compose projects where source is bind-mounted with hot-reload but Python/Node dependencies are baked into images at build time. Use when uploading source to a deploy target and needing to decide between full image rebuild vs starting existing images — wrong choice wastes 5-47 minutes per deploy or leaves the container running stale `.venv` / `node_modules`.
---

# Deploy Strategy After Upload (FastAPI + Vue + Docker Compose)

> 通用版本，适用于任何 FastAPI + Vue 项目用 docker-compose 部署 + bind-mount hot-reload 的场景。
> 项目特定版本（如脚本名、服务器地址）请自行替换。

## Core Principle

**Don't rebuild blindly; don't skip rebuild blindly.** Three questions decide:

1. Did `pyproject.toml` / `uv.lock` change? → `.venv` is baked into image → rebuild
2. Did frontend dependency or build config change? → `node_modules` baked into image → rebuild frontend
3. Did `Dockerfile` / `docker-compose.yml` change? → rebuild

If **all no**, and only `backend/**/*.py` or `frontend/src/**` changed → no rebuild, just start.

## Decision Matrix

| Changed path | Bind-mounted? | Baked into image? | Action |
|---|---|---|---|
| `backend/**/*.py` | ✓ (typical `./backend:/app/backend`) | ✓ (`COPY` too, but mount wins) | **No rebuild** — uvicorn `--reload` picks up bind-mount changes |
| `pyproject.toml`, `uv.lock` | ✗ | ✓ (builder `uv sync`) | **Rebuild backend** |
| `frontend/package.json`, `frontend/vite.config.ts` | ✗ | ✓ | **Rebuild frontend** |
| `frontend/src/**` | ✗ | ✗ (Vite build → `dist/`) | **Rebuild frontend** |
| `Dockerfile`, `docker-compose.yml` | n/a | n/a | **Rebuild** |
| `scripts/**` (host-side) | ✗ | ✗ | **Sync only** — script never enters container |
| `docs/**`, `CHANGELOG.md`, `README.md` | ✗ | ✗ | **No rebuild** |
| `.env.local`, `.env` | bind-mount (typical) | ✗ | **No rebuild** — container restart suffices |

## How to Verify (don't trust this matrix blindly)

Read the actual `Dockerfile` and `docker-compose.yml`:

- `COPY X Y` in Dockerfile → X is **baked** at image build time
- `- ./host/path:/container/path` under `volumes:` → host path is **bind-mounted**, overrides any `COPY`
- A path that is **only** `COPY`'d (no mount) = needs rebuild to update
- A path that is **bind-mounted** + has hot-reload (`uvicorn --reload`, `vite dev`) = no rebuild

To audit any project: read `Dockerfile` for `COPY` lines (baked paths) and `docker-compose.yml` for `volumes:` (bind-mounted paths). Intersection = hot-reload-only; `COPY`-only paths = needs rebuild.

## Workflow

1. **Sync code** to server (use whatever host-side upload script your project has — `rsync`, `scp`, `tar+ssh`, etc.):
   ```bash
   # Replace with your project's host-side upload command
   rsync -avz --exclude '.git' --exclude 'node_modules' --exclude '.venv' \
       ./ <user>@<server-ip>:<server-project-dir>/
   # OR
   tar czf - --exclude='./.git' --exclude='./node_modules' --exclude='./.venv' . \
       | ssh <user>@<server-ip> "tar xzf - -C <server-project-dir>"
   ```

2. **Identify changed files** on server:
   ```bash
   cd <server-project-dir>
   git status
   git diff --name-only HEAD
   ```

3. **Apply decision matrix** above.

4. **Run on server** (`<user>@<server-ip>`, project at `<server-project-dir>`):
   ```bash
   # Option A: Rebuild (backend + frontend images)
   ssh <user>@<server-ip> "cd <server-project-dir> && bash scripts/rebuild-deploy.sh"

   # Option B: No rebuild — start existing images
   ssh <user>@<server-ip> "cd <server-project-dir> && bash scripts/start-dev.sh docker"
   ```

5. **Verify**:
   ```bash
   curl http://<server-ip>:<backend-port>/<health-endpoint>
   # e.g. http://10.0.0.5:8000/api/health or /docs
   ```

## Your project needs these 3 scripts

Each project adapting this skill should provide:

| Script | Runs where | Purpose |
|---|---|---|
| `<your-sync-script>.sh` | host | Upload source to server, excluding `.git` / `node_modules` / `.venv` / cache dirs |
| `scripts/rebuild-deploy.sh` | server | `docker compose build` for changed components, then `up -d` |
| `scripts/start-dev.sh` | server | Just `docker compose up -d` (assumes images already built) |

Suggested minimal `scripts/rebuild-deploy.sh` template:

```bash
#!/bin/bash
set -e
cd "$(dirname "$0")/.."  # project root

docker compose down
docker compose build backend frontend  # adjust service names
docker compose up -d
docker compose logs --tail=50 backend frontend
```

Adapt service names (`backend` / `frontend`) and `docker compose` command flavor (`docker-compose` vs `docker compose`) to your project.

## Red Lines — Don't Rationalize

| Rationalization | Why it's wrong |
|---|---|
| "保险起见每次都 rebuild" | Wastes 5-47 min/deploy. The matrix exists precisely so you don't. |
| "bind-mount 了就不需要 rebuild" | True for app source. **False** for `.venv` / `node_modules` — those are not bind-mounted. |
| "只改了 `backend/*.py`，应该不用 rebuild" | Correct **only if** `pyproject.toml`/`uv.lock` also unchanged. Always check both. |
| "前端只改了 `src/`，package.json 没动就不 rebuild" | `src/` is consumed by Vite build → `dist/` is baked into nginx-served output. Rebuild. |
| "scripts/ 也算源码，得 rebuild" | `scripts/sync_local_data.py`, `scripts/periodic_sync.sh` 等 run on host with host's venv + Redis. Never enter container. Sync alone is enough. |
| "重启容器就 pick up 新代码了" | Container restart doesn't change image layers. Bind-mount source change is already live; image-baked change is not. |

## Adapting Within FastAPI + Vue

To add a third component (e.g. browser extension, Redis, worker):

1. Add a row to the decision matrix for the new component's paths
2. Add a `sync_lock_<name>()` function (if it has a lockfile-baked dep): use the toolchain's lock command (`uv lock`, `npm install`, `cargo generate-lockfile`, etc.)
3. In `scripts/rebuild-deploy.sh`, add the new service to `docker compose build`

To swap backend toolchain (`uv` → `poetry` / `pip-tools` / etc.):
- Edit `sync_lock_backend` to call the new toolchain's lock command
- The matrix stays the same

To swap frontend toolchain (`npm` → `yarn` / `pnpm` / `bun`):
- Edit `sync_lock_frontend` similarly

## Adapting to Other Stacks (beyond FastAPI + Vue)

The decision matrix logic is universal — only the lockfile commands change:

| Stack | Backend lock | Frontend lock |
|---|---|---|
| FastAPI + Vue (default) | `uv lock` | `npm install` |
| Django + React | `poetry lock` | `yarn install --frozen-lockfile` |
| Flask + Angular | `pip-compile` | `npm ci` |
| Rails + Vue | `bundle install` | `pnpm install --frozen-lockfile` |
| Go + React | `go mod tidy` | `yarn install` |
| Rust + Svelte | `cargo generate-lockfile` | `pnpm install` |

The matrix (bind-mount vs COPY) is the same regardless of language.