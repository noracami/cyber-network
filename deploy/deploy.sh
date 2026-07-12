#!/bin/bash
# Grid Master 部署腳本（由 wisp 的 webhook 服務觸發）
# 放置於 wisp:/opt/grid-master/scripts/deploy.sh
# v1.5 起牌局狀態持久化於 Postgres（room_snapshots），重啟自動續局——
# 隨時可部署，玩家只感受到數秒斷線重連。（?force 參數保留相容，已無作用）
set -u
cd /opt/grid-master

docker compose -f docker-compose.prod.yml pull app 2>&1
docker compose -f docker-compose.prod.yml up -d 2>&1
docker image prune -f 2>&1
echo "Deploy completed at $(date)"
