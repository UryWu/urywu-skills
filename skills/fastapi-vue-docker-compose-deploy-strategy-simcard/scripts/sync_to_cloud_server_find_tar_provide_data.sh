#!/bin/bash
# sync_to_cloud_server_find_tar_provide_data.sh
# 将本机代码同步到云服务器（请按需填入 SERVER / REMOTE_DIR 变量，或用环境变量注入）
# 通过 find + tar + ssh 管道，排除 git/venv/cache 等

set -e

# --- Configuration (override via env or edit below) -------------------------
: "${SERVER:=<user>@<server-ip>}"            # e.g. deploy@10.0.0.5
: "${REMOTE_DIR:=<server-project-dir>}"     # e.g. /opt/myapp
# -----------------------------------------------------------------------------

START_SECONDS=$(date +%s)

echo "================================================"
echo "  开始同步到云服务器..."
echo "================================================"
echo ""

# 先创建一个文件列表（排除：git/venv/cache + 非必需的历史爬取 JSON）
# data/callbacks/（运行时按需创建）路径保留，但目前不存在则自动跳过
find ./ \
    -type f \
    -not -path "*/.git/*" \
    -not -path "*/.venv/*" \
    -not -path "*/__pycache__/*" \
    -not -path "*Shortcut.lnk*" \
    -not -path "*/data/product_list_*.json" \
    -not -path "*/data/product_detail_*.json" \
    -not -path "*/data/merged_product_*.json" \
    -print0 | tar czf - --null -T - | \
    ssh "$SERVER" "mkdir -p '$REMOTE_DIR' && cd '$REMOTE_DIR' && tar xzf -"

END_SECONDS=$(date +%s)
ELAPSED=$((END_SECONDS - START_SECONDS))

# 换算为 分:秒
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

echo ""
echo "================================================"
echo "  同步完成！用时 ${MINUTES}m ${SECONDS}s"
echo "================================================"