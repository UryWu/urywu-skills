#!/bin/bash
# rebuild-deploy.sh — Docker Compose 完整重构 + 部署
# 在服务器上执行：重构后端镜像 + 构建前端 + 重启容器
#
# 用法:
#   bash rebuild-deploy.sh              # 完整构建部署
#   bash rebuild-deploy.sh --no-cache   # 强制从头构建（不用缓存层）

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

NO_CACHE="${1:+--no-cache}"

echo "================================================"
echo "  手机流量卡分销平台 — 完整重构部署"
echo "================================================"
echo "  💡 加 --no-cache 跳过 Docker 缓存，强制检查源码构建问题"
echo ""

# 步骤 1：重构后端镜像
# ⚠️ docker compose build 只构建镜像，不影响正在运行的旧容器。
#    后面的 docker compose up -d 会自动检测镜像变化→停旧容器→启新容器，
#    所以不需要提前 docker compose down。
# ⏳ CentOS 7 下实测首次构建约 47 分 17 秒（2837s），主要耗时在 uv sync
#    下载 numpy/pandas/sqlalchemy 等依赖。后续构建会利用 docker 缓存层
#    大幅加快（仅变动层重新构建）。
# ⚠️ --no-cache 能发现源码构建问题：Docker 缓存可能跳过 vue-tsc 检测，
#    导致未使用的 import、类型错误等问题被掩盖。如果页面异常请加 --no-cache 试试。
echo "步骤 1/3：构建后端镜像..."
docker compose build backend $NO_CACHE
echo "  ✅ 后端镜像构建完成"
echo ""

# 步骤 2：构建前端
# ⚠️ 如果前端页面未更新，可能是 Docker 缓存了旧的构建层，
#    加上 --no-cache 可跳过缓存强制重检源码。
echo "步骤 2/3：构建前端..."
docker compose build frontend-build $NO_CACHE
docker compose run --rm frontend-build
echo "  ✅ 前端构建完成"
echo ""

# 步骤 3：启动/重启后端
echo "步骤 3/3：启动后端容器..."
docker compose up -d backend
echo "  ✅ 后端已启动"
echo ""

echo "================================================"
echo "  部署完成"
echo "================================================"
echo ""
echo "  docker compose logs -f   查看日志"
echo "  docker compose down      停止服务"
echo ""
