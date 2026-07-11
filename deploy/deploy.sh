#!/bin/bash
# Grid Master 部署腳本（由 wisp 的 webhook 服務觸發）
# 放置於 wisp:/opt/grid-master/scripts/deploy.sh
# 用法：deploy.sh [force] —— 預設有進行中牌局就中止（遊戲狀態在記憶體，重啟即蒸發）
set -u
cd /opt/grid-master

FORCE="${1:-}"

in_game=$(curl -fsS --max-time 3 http://127.0.0.1:8100/api/activity 2>/dev/null |
  grep -o '"in_game":[0-9]*' | head -1 | cut -d: -f2)
in_game="${in_game:-0}"

if [ "$in_game" -gt 0 ] && [ "$FORCE" != "force" ]; then
  echo "拒絕部署：有 $in_game 局進行中（webhook 加 ?force=force 可強制）"
  exit 1
fi

docker compose -f docker-compose.prod.yml pull app 2>&1
docker compose -f docker-compose.prod.yml up -d 2>&1
docker image prune -f 2>&1
echo "Deploy completed at $(date)"
