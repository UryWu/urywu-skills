#!/bin/bash
# start-dev.sh — 手机流量卡分销平台开发环境启动脚本（Linux / macOS）
# 支持 Docker 和原生两种模式。
#
# Docker 模式（推荐，绕过 CentOS 7 glibc 限制）：
#   bash start-dev.sh docker
# 原生模式：
#   bash start-dev.sh native

set -e

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

MODE="${1:-docker}"  # 默认 Docker 模式

echo "================================================"
echo "  手机流量卡分销平台开发环境启动"
echo "================================================"
echo ""

# ── Docker 模式 ─────────────────────────────────
docker_mode() {
    echo "[INFO] 使用 Docker 模式"

    # 检查 Docker
    if ! command -v docker >/dev/null 2>&1; then
        echo "[ERROR] Docker 未安装"
        echo "  请先安装 Docker:"
        echo "  curl -fsSL https://get.docker.com | bash"
        exit 1
    fi
    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        echo "[ERROR] docker compose 插件未安装"
        exit 1
    fi
    echo "[OK] Docker 已安装"
    echo ""

    # 检查 .env.local
    if [ ! -f .env.local ]; then
        if [ -f .env.example ]; then
            cp .env.example .env.local
            echo "[OK] 已创建 .env.local 文件"
            echo "  请编辑 .env.local 文件，配置开发环境参数"
        else
            echo "[ERROR] .env.example 不存在，请手动创建 .env.local"
            exit 1
        fi
    else
        echo "[OK] .env.local 文件已存在"
    fi
    echo ""

    # 构建前端 dist/
    echo "步骤1：构建前端..."
    docker compose run --rm frontend-build && echo "[OK] 前端构建完成" || {
        echo "[ERROR] 前端构建失败"
        exit 1
    }
    echo ""

    # 启动后端容器（热重载，后台运行）
    echo "步骤2：启动后端..."
    echo "  → 正在拉取并构建后端镜像（首次需下载 python 镜像，约 1-2 分钟）..."
    docker compose up -d backend
    if [ $? -eq 0 ]; then
        echo "[OK] 后端已启动"
    else
        echo "[ERROR] 后端启动失败，尝试查看日志: docker compose logs backend"
        exit 1
    fi
    echo ""

    echo "================================================"
    echo "  开发环境准备完成！"
    echo "================================================"
    echo ""
    echo "访问地址:"
    echo "  后端 API:   http://localhost:8000"
    echo "  前端界面:   http://<server-ip>（nginx）"
    echo "  API 文档:   http://localhost:8000/docs"
    echo ""
    echo "管理命令:"
    echo "  查看日志:    docker compose logs -f"
    echo "  重启后端:    docker compose restart backend"
    echo "  重建前端:    docker compose run --rm frontend-build"
    echo "  停止所有:    docker compose down"
    echo ""
    echo "环境检查:"
    echo "  健康检查:   curl http://localhost:8000/api/health"
    echo ""
}

# ── 原生模式 ────────────────────────────────────
native_mode() {
    echo "[INFO] 使用原生模式"

    MISSING_TOOLS=""

    check_cmd() {
        local name="$1" cmd="$2" hint="${3:-}"
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "[OK] $name 已安装"
            return 0
        else
            MISSING_TOOLS="$MISSING_TOOLS  - $name（${hint:-未安装}）"$'\n'
            return 1
        fi
    }

    check_cmd "Python" "python3" "请安装 Python 3.12+"
    check_cmd "uv" "uv" "请安装 uv: pip3 install uv"

    if [ -n "$MISSING_TOOLS" ]; then
        echo ""
        echo "[ERROR] 以下必需工具缺失:"
        echo "$MISSING_TOOLS"
        exit 1
    fi

    # 环境配置
    echo ""
    if [ ! -f .env.local ]; then
        if [ -f .env.example ]; then
            cp .env.example .env.local
            echo "[OK] 已创建 .env.local 文件"
        else
            echo "[ERROR] .env.example 不存在"
            exit 1
        fi
    fi

    # 安装 Python 依赖
    echo ""
    echo "安装 Python 依赖..."
    uv sync

    # 启动后端
    echo ""
    echo "启动后端（原生）..."
    nohup uv run uvicorn backend.app:app --reload --host 127.0.0.1 --port 8000 > app.log 2>&1 &
    BACKEND_PID=$!
    echo "[OK] 后端已启动（PID: $BACKEND_PID）"

    # 前端提示
    echo ""
    echo "[WARN] 前端无法在本文本服务器运行（glibc 过旧）"
    echo "  请用 Docker 构建前端: docker compose run --rm frontend-build"
    echo "  或在本机构建后上传 dist/ 目录"
    echo ""

    echo "访问:"
    echo "  后端 API:   http://localhost:8000"
    echo "  前端界面:   http://<server-ip>（nginx 提供）"
}

# ── 入口 ────────────────────────────────────────
case "$MODE" in
    docker|d)
        docker_mode
        ;;
    native|n)
        native_mode
        ;;
    *)
        echo "用法: bash start-dev.sh [docker|native]"
        echo "  docker (默认) - 使用 Docker Compose 运行"
        echo "  native       - 宿主机原生运行（仅后端）"
        exit 1
        ;;
esac
