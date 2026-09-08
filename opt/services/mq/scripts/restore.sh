#!/bin/bash

set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$1" ]; then
    echo
    echo "Usage:"
    echo "  ./restore.sh <backup_directory>"
    echo
    echo "Example:"
    echo "  ./restore.sh backups/20260907_180500"
    echo
    exit 1
fi

BACKUP_DIR="$(cd "$1" 2>/dev/null && pwd)" || {
    echo "[ERROR] Backup directory not found: $1"
    exit 1
}

COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo
echo "============================================================"
echo " MQ Infrastructure Restore"
echo "============================================================"
echo
echo "Backup:"
echo "${BACKUP_DIR}"
echo

echo -e "${RED}WARNING!${NC}"
echo
echo "此操作会覆盖以下 Docker Volume 中的数据："
echo
echo "  minimal_pgdata"
echo "  minimal_esdata"
echo "  minimal_kafkadata"
echo "  minimal_rmqdata"
echo
echo "当前环境中的数据可能会丢失。"
echo

read -r -p "确认继续请输入 YES: " CONFIRM

if [ "${CONFIRM}" != "YES" ]; then
    echo
    echo "Restore cancelled."
    exit 0
fi

cd "${BASE_DIR}"


# ============================================================
# 1. 检查备份
# ============================================================

echo
echo "------------------------------------------------------------"
echo "1. Checking backup"
echo "------------------------------------------------------------"

[ -f "${BACKUP_DIR}/config/docker-compose.yml" ] \
    || {
        echo "[ERROR] docker-compose.yml not found"
        exit 1
    }

if [ -f "${BACKUP_DIR}/config/.env" ]; then
    echo "[OK] .env found"
fi

if [ -f "${BACKUP_DIR}/postgres/vector_db.dump" ]; then
    echo "[OK] PostgreSQL backup found"
else
    echo -e "${YELLOW}[WARN] PostgreSQL backup not found${NC}"
fi

if [ -f "${BACKUP_DIR}/rocketmq/rmqdata.tar.gz" ]; then
    echo "[OK] RocketMQ backup found"
else
    echo -e "${YELLOW}[WARN] RocketMQ backup not found${NC}"
fi

if [ -f "${BACKUP_DIR}/kafka/kafkadata.tar.gz" ]; then
    echo "[OK] Kafka backup found"
else
    echo -e "${YELLOW}[WARN] Kafka backup not found${NC}"
fi

if [ -f "${BACKUP_DIR}/elasticsearch/esdata.tar.gz" ]; then
    echo "[OK] Elasticsearch backup found"
else
    echo -e "${YELLOW}[WARN] Elasticsearch backup not found${NC}"
fi


# ============================================================
# 2. 停止服务
# ============================================================

echo
echo "------------------------------------------------------------"
echo "2. Stopping services"
echo "------------------------------------------------------------"

docker compose down

echo "[OK] Services stopped"


# ============================================================
# 3. 创建 Docker Volume
# ============================================================

echo
echo "------------------------------------------------------------"
echo "3. Preparing volumes"
echo "------------------------------------------------------------"

docker volume create minimal_pgdata >/dev/null
docker volume create minimal_esdata >/dev/null
docker volume create minimal_kafkadata >/dev/null
docker volume create minimal_rmqdata >/dev/null

echo "[OK] Volumes ready"


# ============================================================
# 4. Restore PostgreSQL
# ============================================================

if [ -f "${BACKUP_DIR}/postgres/vector_db.dump" ]; then

    echo
    echo "------------------------------------------------------------"
    echo "4. Restoring PostgreSQL"
    echo "------------------------------------------------------------"

    docker compose up -d pgvector

    echo "Waiting PostgreSQL..."

    for i in $(seq 1 60); do

        STATUS=$(docker inspect \
            -f '{{.State.Health.Status}}' \
            minimal_pgvector 2>/dev/null || true)

        if [ "${STATUS}" = "healthy" ]; then
            break
        fi

        if [ "$i" -eq 60 ]; then
            echo "[ERROR] PostgreSQL startup timeout"
            docker logs --tail=100 minimal_pgvector
            exit 1
        fi

        sleep 2
    done

    POSTGRES_USER=$(grep '^POSTGRES_USER=' "${BASE_DIR}/.env" \
        | cut -d'=' -f2-)

    POSTGRES_DB=$(grep '^POSTGRES_DB=' "${BASE_DIR}/.env" \
        | cut -d'=' -f2-)

    cat "${BACKUP_DIR}/postgres/vector_db.dump" \
        | docker exec -i minimal_pgvector \
        pg_restore \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" \
        --clean \
        --if-exists \
        --no-owner \
        --no-privileges \
        || true

    echo "[OK] PostgreSQL restored"

else

    echo
    echo "[SKIP] PostgreSQL backup not found"

fi


# ============================================================
# 5. 停止 PostgreSQL
# ============================================================

docker compose stop pgvector >/dev/null 2>&1 || true


# ============================================================
# 6. Restore RocketMQ
# ============================================================

if [ -f "${BACKUP_DIR}/rocketmq/rmqdata.tar.gz" ]; then

    echo
    echo "------------------------------------------------------------"
    echo "5. Restoring RocketMQ"
    echo "------------------------------------------------------------"

    docker run --rm \
        --user root \
        -v minimal_rmqdata:/data \
        -v "${BACKUP_DIR}/rocketmq:/backup:ro" \
        alpine:3.20 \
        sh -c "
            rm -rf /data/*
            tar xzf /backup/rmqdata.tar.gz -C /data
        "

    docker run --rm \
        --user root \
        -v minimal_rmqdata:/home/rocketmq/store \
        apache/rocketmq:5.3.1 \
        chown -R rocketmq:rocketmq /home/rocketmq/store

    echo "[OK] RocketMQ restored"

else

    echo
    echo "[SKIP] RocketMQ backup not found"

fi


# ============================================================
# 7. Restore Kafka
# ============================================================

if [ -f "${BACKUP_DIR}/kafka/kafkadata.tar.gz" ]; then

    echo
    echo "------------------------------------------------------------"
    echo "6. Restoring Kafka"
    echo "------------------------------------------------------------"

    docker run --rm \
        --user root \
        -v minimal_kafkadata:/data \
        -v "${BACKUP_DIR}/kafka:/backup:ro" \
        alpine:3.20 \
        sh -c "
            rm -rf /data/*
            tar xzf /backup/kafkadata.tar.gz -C /data
        "

    echo "[OK] Kafka restored"

else

    echo
    echo "[SKIP] Kafka backup not found"

fi


# ============================================================
# 8. Restore Elasticsearch
# ============================================================

if [ -f "${BACKUP_DIR}/elasticsearch/esdata.tar.gz" ]; then

    echo
    echo "------------------------------------------------------------"
    echo "7. Restoring Elasticsearch"
    echo "------------------------------------------------------------"

    docker run --rm \
        --user root \
        -v minimal_esdata:/data \
        -v "${BACKUP_DIR}/elasticsearch:/backup:ro" \
        alpine:3.20 \
        sh -c "
            rm -rf /data/*
            tar xzf /backup/esdata.tar.gz -C /data
        "

    echo "[OK] Elasticsearch restored"

else

    echo
    echo "[SKIP] Elasticsearch backup not found"

fi


# ============================================================
# 9. 修复 RocketMQ 权限
# ============================================================

echo
echo "------------------------------------------------------------"
echo "8. Fixing RocketMQ permissions"
echo "------------------------------------------------------------"

ROCKETMQ_VERSION=$(grep '^ROCKETMQ_VERSION=' "${BASE_DIR}/.env" \
    | cut -d'=' -f2-)

docker run --rm \
    --user root \
    -v minimal_rmqdata:/home/rocketmq/store \
    "apache/rocketmq:${ROCKETMQ_VERSION}" \
    chown -R rocketmq:rocketmq /home/rocketmq/store

echo "[OK] RocketMQ permissions fixed"


# ============================================================
# 10. 启动全部服务
# ============================================================

echo
echo "------------------------------------------------------------"
echo "9. Starting all services"
echo "------------------------------------------------------------"

docker compose up -d

echo "[OK] Services started"


# ============================================================
# 11. 等待
# ============================================================

echo
echo "------------------------------------------------------------"
echo "10. Waiting for services"
echo "------------------------------------------------------------"

sleep 10

docker compose ps


# ============================================================
# 12. 最终检查
# ============================================================

echo
echo "============================================================"
echo " Restore completed"
echo "============================================================"
echo

echo "请继续执行："
echo
echo "  ./mq.sh status"
echo "  ./mq.sh test"
echo