---
name: fastapi-vue-docker-compose-deploy-strategy-simcard
description: Use when uploading source code to a remote Docker-Compose deploy target and needing to decide between full image rebuild (`rebuild-deploy.sh`) versus just starting existing images (`start-dev.sh`) — applies to FastAPI + Vue projects where source is bind-mounted with hot-reload but Python/Node dependencies are baked into images at build time; a wrong choice wastes 5-47 minutes per deploy or leaves the container running stale `.venv` / `node_modules`.
---

# Deploy Strategy After Upload

## Core Principle

**Don't rebuild blindly; don't skip rebuild blindly.** Three questions decide:

1. Did `pyproject.toml` / `uv.lock` change? → `.venv` is baked into image → rebuild
2. Did frontend dependency or build config change? → `node_modules` baked into image → rebuild frontend
3. Did `Dockerfile` / `docker-compose.yml` change? → rebuild

If **all no**, and only `backend/**/*.py` or `frontend/src/**` changed → no rebuild, just start.

## Decision Matrix (this project's layout)

| Changed path | Bind-mounted? | Baked into image? | Action |
|---|---|---|---|
| `backend/**/*.py` | ✓ `./backend:/app/backend` | ✓ (`COPY` too, but mount wins) | **No rebuild** — uvicorn `--reload` picks up bind-mount changes |
| `pyproject.toml`, `uv.lock` | ✗ | ✓ (builder `uv sync`) | **Rebuild backend** |
| `frontend/package.json`, `frontend/vite.config.ts` | ✗ | ✓ | **Rebuild frontend** |
| `frontend/src/**` | ✗ | ✗ (Vite output) | **Rebuild frontend** |
| `Dockerfile`, `docker-compose.yml` | n/a | n/a | **Rebuild** |
| `scripts/**` (host-side) | ✗ | ✗ | **Sync only** — script never enters container |
| `docs/**`, `CHANGELOG.md`, `README.md` | ✗ | ✗ | **No rebuild** |
| `.env.local`, `.env` | bind-mount | ✗ | **No rebuild** — container restart suffices |

## How to Verify (don't trust this table blindly)

Read the actual `Dockerfile` and `docker-compose.yml`:

- `COPY X Y` in Dockerfile → X is **baked** at image build time
- `- ./host/path:/container/path` under `volumes:` → host path is **bind-mounted**, overrides any `COPY`
- A path that is **only** `COPY`'d (no mount) = needs rebuild to update
- A path that is **bind-mounted** + has hot-reload (`uvicorn --reload`, `vite dev`) = no rebuild

## Workflow

1. Sync code (host-side, bundled `scripts/sync_to_cloud_server_find_tar_provide_data.sh`):
   ```bash
   cd <project-root>
   bash scripts/sync_to_cloud_server_find_tar_provide_data.sh
   ```
2. Identify changed files: `git status` + `git diff --name-only HEAD`
3. Apply decision matrix above
4. Run on server (`<user>@<server-ip>`, project at `<server-project-dir>`):
   ```bash
   # Rebuild (backend + frontend images)
   ssh <user>@<server-ip> "cd <server-project-dir> && bash scripts/rebuild-deploy.sh"

   # No rebuild — start existing images
   ssh <user>@<server-ip> "cd <server-project-dir> && bash scripts/start-dev.sh docker"
   ```
5. Verify: `curl http://<server-ip>:8000/api/health` (or `/docs`)

## Red Lines — Don't Rationalize

| Rationalization | Why it's wrong |
|---|---|
| "保险起见每次都 rebuild" | Wastes 5-47 min/deploy. The matrix exists precisely so you don't. |
| "bind-mount 了就不需要 rebuild" | True for app source. **False** for `.venv` / `node_modules` — those are not bind-mounted. |
| "只改了 `backend/*.py`，应该不用 rebuild" | Correct **only if** `pyproject.toml`/`uv.lock` also unchanged. Always check both. |
| "前端只改了 `src/`，package.json 没动就不 rebuild" | `src/` is consumed by Vite build → `dist/` is baked into nginx-served output. Rebuild. |
| "scripts/ 也算源码，得 rebuild" | `scripts/sync_local_data.py`, `scripts/periodic_sync.sh` 等 run on host with host's venv + Redis. Never enter container. Sync alone is enough. |
| "重启容器就 pick up 新代码了" | Container restart doesn't change image layers. Bind-mount source change is already live; image-baked change is not. |

## Bundled Scripts

Three scripts from the source project are bundled for self-containment; **the project canonical copies at `<project>/scripts/` are the single source of truth**. Treat the bundled copies as reference snapshots and keep them in sync via your project's `sync_skill_copies.sh` (not bundled; recreate it from the pattern in `fastapi-vue-version-bump`).

- `scripts/sync_to_cloud_server_find_tar_provide_data.sh` — host-side upload (creates tarball, transfers to server, extracts)
- `scripts/rebuild-deploy.sh` — server-side: rebuild backend + frontend images then restart
- `scripts/start-dev.sh` — server-side: just start existing images (assumes already-built)

## Adapting to Other Projects

Replace placeholders (`<user>`, `<server-ip>`, `<server-project-dir>`) and the three script paths. The decision matrix is universal for any project where:

- App source is bind-mounted with hot-reload
- Dependencies (`uv.lock` / `package-lock.json` / `requirements.txt` / `Pipfile.lock`) are baked into image at build time
- A "full rebuild" script and a "start existing images" script both exist

To audit any project: read `Dockerfile` for `COPY` lines (baked paths) and `docker-compose.yml` for `volumes:` (bind-mounted paths). Intersection = hot-reload-only; `COPY`-only paths = needs rebuild.