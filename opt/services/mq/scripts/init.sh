#!/bin/bash

# ============================================================
# MQ Infrastructure Init Script
#
# PostgreSQL + pgvector
# Elasticsearch
# Kafka KRaft
# RocketMQ NameServer + Broker
#
# Usage:
#   bash init.sh
# ============================================================

set -e

# ============================================================
# 基础配置
# ============================================================

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
ENV_FILE="${BASE_DIR}/.env"
BROKER_CONF="${BASE_DIR}/broker.conf"

RMQ_VOLUME="minimal_rmqdata"

RMQ_IMAGE="apache/rocketmq:5.3.1"

echo
echo "============================================================"
echo " MQ Infrastructure Initialization"
echo "============================================================"
echo
echo "BASE_DIR: ${BASE_DIR}"
echo


# ============================================================
# 颜色
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'


# ============================================================
# 错误处理
# ============================================================

error_exit() {
    echo
    echo -e "${RED}[ERROR] $1${NC}"
    echo
    exit 1
}


success() {
    echo -e "${GREEN}[OK] $1${NC}"
}


info() {
    echo -e "${YELLOW}[INFO] $1${NC}"
}


# ============================================================
# 1. 检查 Docker
# ============================================================

echo "------------------------------------------------------------"
echo "1. Checking Docker"
echo "------------------------------------------------------------"

if ! command -v docker >/dev/null 2>&1; then
    error_exit "Docker 未安装，请先安装 Docker"
fi

success "Docker 已安装"

if ! docker info >/dev/null 2>&1; then
    error_exit "Docker 服务未运行，请启动 Docker"
fi

success "Docker 服务正常"


# ============================================================
# 2. 检查 Docker Compose
# ============================================================

echo
echo "------------------------------------------------------------"
echo "2. Checking Docker Compose"
echo "------------------------------------------------------------"

if ! docker compose version >/dev/null 2>&1; then
    error_exit "Docker Compose 不可用"
fi

COMPOSE_VERSION=$(docker compose version --short)

success "Docker Compose ${COMPOSE_VERSION}"


# ============================================================
# 3. 检查文件
# ============================================================

echo
echo "------------------------------------------------------------"
echo "3. Checking configuration files"
echo "------------------------------------------------------------"

[ -f "${COMPOSE_FILE}" ] \
    || error_exit "找不到 ${COMPOSE_FILE}"

[ -f "${ENV_FILE}" ] \
    || error_exit "找不到 ${ENV_FILE}"

[ -f "${BROKER_CONF}" ] \
    || error_exit "找不到 ${BROKER_CONF}"

[ -f "${BASE_DIR}/wait-for-ns.sh" ] \
    || error_exit "找不到 ${BASE_DIR}/scripts/wait-for-ns.sh"

success "配置文件检查通过"


# ============================================================
# 4. 加载 .env
# ============================================================

echo
echo "------------------------------------------------------------"
echo "4. Loading environment"
echo "------------------------------------------------------------"

set -a
source "${ENV_FILE}"
set +a

if [ -z "${SERVER_IP}" ]; then
    error_exit ".env 中没有配置 SERVER_IP"
fi

info "SERVER_IP=${SERVER_IP}"


# ============================================================
# 5. 检查 SERVER_IP
# ============================================================

echo
echo "------------------------------------------------------------"
echo "5. Checking SERVER_IP"
echo "------------------------------------------------------------"

if ! [[ "${SERVER_IP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error_exit "SERVER_IP 格式错误：${SERVER_IP}"
fi

success "SERVER_IP 格式正确"


# ============================================================
# 6. 自动更新 RocketMQ brokerIP1
# ============================================================

echo
echo "------------------------------------------------------------"
echo "6. Updating RocketMQ brokerIP1"
echo "------------------------------------------------------------"

if grep -q "^brokerIP1=" "${BROKER_CONF}"; then

    sed -i \
        "s/^brokerIP1=.*/brokerIP1=${SERVER_IP}/" \
        "${BROKER_CONF}"

else

    echo "" >> "${BROKER_CONF}"
    echo "brokerIP1=${SERVER_IP}" >> "${BROKER_CONF}"

fi

CURRENT_BROKER_IP=$(grep "^brokerIP1=" "${BROKER_CONF}" | cut -d'=' -f2)

if [ "${CURRENT_BROKER_IP}" != "${SERVER_IP}" ]; then
    error_exit "RocketMQ brokerIP1 更新失败"
fi

success "RocketMQ brokerIP1=${SERVER_IP}"


# ============================================================
# 7. 检查 wait-for-ns.sh 权限
# ============================================================

echo
echo "------------------------------------------------------------"
echo "7. Checking RocketMQ startup script"
echo "------------------------------------------------------------"

chmod +x "${BASE_DIR}/wait-for-ns.sh"

success "wait-for-ns.sh 可执行"


# ============================================================
# 8. 创建 RocketMQ Volume
# ============================================================

echo
echo "------------------------------------------------------------"
echo "8. Preparing RocketMQ volume"
echo "------------------------------------------------------------"

if docker volume inspect "${RMQ_VOLUME}" >/dev/null 2>&1; then

    info "Volume ${RMQ_VOLUME} 已存在"

else

    docker volume create "${RMQ_VOLUME}" >/dev/null

    success "创建 Volume ${RMQ_VOLUME}"

fi


# ============================================================
# 9. 修复 RocketMQ Store 权限
# ============================================================

echo
echo "------------------------------------------------------------"
echo "9. Fixing RocketMQ store permissions"
echo "------------------------------------------------------------"

docker run --rm \
    --user root \
    -v "${RMQ_VOLUME}:/home/rocketmq/store" \
    "${RMQ_IMAGE}" \
    chown -R rocketmq:rocketmq /home/rocketmq/store

success "RocketMQ Store 权限已修复"


# ============================================================
# 10. 验证 RocketMQ Store
# ============================================================

echo
echo "------------------------------------------------------------"
echo "10. Verifying RocketMQ store"
echo "------------------------------------------------------------"

STORE_OWNER=$(docker run --rm \
    --user root \
    -v "${RMQ_VOLUME}:/home/rocketmq/store" \
    "${RMQ_IMAGE}" \
    stat -c '%U:%G' /home/rocketmq/store)

if [ "${STORE_OWNER}" != "rocketmq:rocketmq" ]; then
    error_exit "RocketMQ Store 权限错误：${STORE_OWNER}"
fi

success "RocketMQ Store owner=${STORE_OWNER}"


# ============================================================
# 11. Compose 配置检查
# ============================================================

echo
echo "------------------------------------------------------------"
echo "11. Validating Docker Compose"
echo "------------------------------------------------------------"

cd "${BASE_DIR}"

docker compose config --quiet

success "Docker Compose 配置正确"


# ============================================================
# 12. 启动服务
# ============================================================

echo
echo "------------------------------------------------------------"
echo "12. Starting services"
echo "------------------------------------------------------------"

docker compose up -d

success "Docker Compose 启动完成"


# ============================================================
# 13. 等待容器启动
# ============================================================

echo
echo "------------------------------------------------------------"
echo "13. Waiting for containers"
echo "------------------------------------------------------------"

sleep 5

docker compose ps


# ============================================================
# 14. 等待 RocketMQ NameServer
# ============================================================

echo
echo "------------------------------------------------------------"
echo "14. Checking RocketMQ NameServer"
echo "------------------------------------------------------------"

for i in $(seq 1 30); do

    if docker exec minimal_rmqnamesrv \
        bash -c "echo > /dev/tcp/127.0.0.1/9876" \
        >/dev/null 2>&1; then

        success "RocketMQ NameServer 已启动"
        break

    fi

    if [ "$i" -eq 30 ]; then
        error_exit "RocketMQ NameServer 启动超时"
    fi

    echo "Waiting NameServer... ${i}/30"

    sleep 2

done


# ============================================================
# 15. 等待 RocketMQ Broker
# ============================================================

echo
echo "------------------------------------------------------------"
echo "15. Checking RocketMQ Broker"
echo "------------------------------------------------------------"

for i in $(seq 1 30); do

    if docker logs minimal_rmqbroker 2>&1 \
        | grep -q "boot success"; then

        success "RocketMQ Broker 启动成功"
        break

    fi

    if [ "$i" -eq 30 ]; then

        echo
        echo "RocketMQ Broker 日志："
        docker logs --tail=100 minimal_rmqbroker

        error_exit "RocketMQ Broker 启动失败或超时"
    fi

    echo "Waiting Broker... ${i}/30"

    sleep 2

done


# ============================================================
# 16. 检查 PostgreSQL
# ============================================================

echo
echo "------------------------------------------------------------"
echo "16. Checking PostgreSQL"
echo "------------------------------------------------------------"

for i in $(seq 1 30); do

    STATUS=$(docker inspect \
        -f '{{.State.Health.Status}}' \
        minimal_pgvector 2>/dev/null || true)

    if [ "${STATUS}" = "healthy" ]; then

        success "PostgreSQL healthy"
        break

    fi

    if [ "$i" -eq 30 ]; then
        error_exit "PostgreSQL 启动超时"
    fi

    echo "Waiting PostgreSQL... ${i}/30"

    sleep 2

done


# ============================================================
# 17. 检查 Elasticsearch
# ============================================================

echo
echo "------------------------------------------------------------"
echo "17. Checking Elasticsearch"
echo "------------------------------------------------------------"

for i in $(seq 1 30); do

    STATUS=$(docker inspect \
        -f '{{.State.Health.Status}}' \
        minimal_es 2>/dev/null || true)

    if [ "${STATUS}" = "healthy" ]; then

        success "Elasticsearch healthy"
        break

    fi

    if [ "$i" -eq 30 ]; then
        error_exit "Elasticsearch 启动超时"
    fi

    echo "Waiting Elasticsearch... ${i}/30"

    sleep 2

done


# ============================================================
# 18. 检查 Kafka
# ============================================================

echo
echo "------------------------------------------------------------"
echo "18. Checking Kafka"
echo "------------------------------------------------------------"

if docker ps \
    --filter "name=minimal_kafka" \
    --filter "status=running" \
    | grep -q minimal_kafka; then

    success "Kafka container 正常运行"

else

    docker logs --tail=100 minimal_kafka

    error_exit "Kafka 启动失败"

fi


# ============================================================
# 19. 最终状态
# ============================================================

echo
echo
echo "============================================================"
echo " ALL SERVICES STATUS"
echo "============================================================"
echo

docker compose ps

echo
echo "============================================================"
echo " RocketMQ Broker"
echo "============================================================"
echo

docker logs minimal_rmqbroker 2>&1 \
    | grep "boot success" \
    | tail -1 || true

echo
echo "============================================================"
echo " Deployment completed successfully"
echo "============================================================"
echo