#!/bin/bash

set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_ROOT="${BASE_DIR}/backups"

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"

echo
echo "============================================================"
echo " MQ Infrastructure Backup"
echo "============================================================"
echo
echo "Backup directory:"
echo "${BACKUP_DIR}"
echo

mkdir -p "${BACKUP_DIR}"

# ============================================================
# 1. Backup configuration
# ============================================================

echo "------------------------------------------------------------"
echo "1. Backup configuration"
echo "------------------------------------------------------------"

mkdir -p "${BACKUP_DIR}/config"

cp "${BASE_DIR}/docker-compose.yml" \
   "${BACKUP_DIR}/config/"

cp "${BASE_DIR}/.env" \
   "${BACKUP_DIR}/config/"

cp "${BASE_DIR}/init.sh" \
   "${BACKUP_DIR}/config/"

cp "${BASE_DIR}/mq.sh" \
   "${BACKUP_DIR}/config/"

cp "${BASE_DIR}/test-rocketmq.sh" \
   "${BACKUP_DIR}/config/"

cp "${BASE_DIR}/rocketmq/broker.conf" \
   "${BACKUP_DIR}/config/"

cp "${BASE_DIR}/scripts/wait-for-ns.sh" \
   "${BACKUP_DIR}/config/"

echo "[OK] Configuration backup completed"


# ============================================================
# 2. PostgreSQL
# ============================================================

echo
echo "------------------------------------------------------------"
echo "2. Backup PostgreSQL"
echo "------------------------------------------------------------"

if docker ps --format '{{.Names}}' | grep -q '^minimal_pgvector$'; then

    mkdir -p "${BACKUP_DIR}/postgres"

    POSTGRES_USER=$(grep '^POSTGRES_USER=' "${BASE_DIR}/.env" \
        | cut -d'=' -f2-)

    POSTGRES_DB=$(grep '^POSTGRES_DB=' "${BASE_DIR}/.env" \
        | cut -d'=' -f2-)

    docker exec minimal_pgvector \
        pg_dump \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" \
        -Fc \
        > "${BACKUP_DIR}/postgres/${POSTGRES_DB}.dump"

    echo "[OK] PostgreSQL backup completed"

else

    echo "[WARN] PostgreSQL container not running, skipped"

fi


# ============================================================
# 3. RocketMQ
# ============================================================

echo
echo "------------------------------------------------------------"
echo "3. Backup RocketMQ"
echo "------------------------------------------------------------"

if docker volume inspect minimal_rmqdata >/dev/null 2>&1; then

    mkdir -p "${BACKUP_DIR}/rocketmq"

    docker run --rm \
        -v minimal_rmqdata:/data:ro \
        -v "${BACKUP_DIR}/rocketmq:/backup" \
        alpine:3.20 \
        tar czf /backup/rmqdata.tar.gz -C /data .

    echo "[OK] RocketMQ data backup completed"

else

    echo "[WARN] RocketMQ volume not found, skipped"

fi


# ============================================================
# 4. Kafka
# ============================================================

echo
echo "------------------------------------------------------------"
echo "4. Backup Kafka"
echo "------------------------------------------------------------"

if docker volume inspect minimal_kafkadata >/dev/null 2>&1; then

    mkdir -p "${BACKUP_DIR}/kafka"

    docker run --rm \
        -v minimal_kafkadata:/data:ro \
        -v "${BACKUP_DIR}/kafka:/backup" \
        alpine:3.20 \
        tar czf /backup/kafkadata.tar.gz -C /data .

    echo "[OK] Kafka data backup completed"

else

    echo "[WARN] Kafka volume not found, skipped"

fi


# ============================================================
# 5. Elasticsearch
# ============================================================

echo
echo "------------------------------------------------------------"
echo "5. Backup Elasticsearch"
echo "------------------------------------------------------------"

if docker volume inspect minimal_esdata >/dev/null 2>&1; then

    mkdir -p "${BACKUP_DIR}/elasticsearch"

    docker run --rm \
        -v minimal_esdata:/data:ro \
        -v "${BACKUP_DIR}/elasticsearch:/backup" \
        alpine:3.20 \
        tar czf /backup/esdata.tar.gz -C /data .

    echo "[OK] Elasticsearch data backup completed"

else

    echo "[WARN] Elasticsearch volume not found, skipped"

fi


# ============================================================
# 6. Backup volume information
# ============================================================

echo
echo "------------------------------------------------------------"
echo "6. Backup volume information"
echo "------------------------------------------------------------"

docker volume inspect \
    minimal_pgdata \
    minimal_esdata \
    minimal_kafkadata \
    minimal_rmqdata \
    > "${BACKUP_DIR}/volume-info.json" 2>/dev/null || true

docker compose ps \
    > "${BACKUP_DIR}/compose-ps.txt" 2>/dev/null || true

echo "[OK] Runtime information saved"


# ============================================================
# 7. Backup size
# ============================================================

echo
echo "------------------------------------------------------------"
echo "7. Backup size"
echo "------------------------------------------------------------"

du -sh "${BACKUP_DIR}"

echo
echo "============================================================"
echo " Backup completed"
echo "============================================================"
echo
echo "Backup:"
echo "${BACKUP_DIR}"
echo