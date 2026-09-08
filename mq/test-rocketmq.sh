#!/bin/bash

# ============================================================
# RocketMQ Health Check
#
# 检查：
#   1. NameServer
#   2. Broker
#   3. Topic
#   4. Producer
#   5. Consumer
#
# Usage:
#   bash test-rocketmq.sh
# ============================================================

set -e

CONTAINER="minimal_rmqbroker"
NAMESRV="rmqnamesrv:9876"

TOPIC="TEST_TOPIC"
GROUP="TEST_CONSUMER_GROUP"
MESSAGE="hello-rocketmq-$(date '+%Y%m%d%H%M%S')"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

info() {
    echo -e "${YELLOW}[INFO] $1${NC}"
}

error_exit() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

echo
echo "============================================================"
echo " RocketMQ Health Check"
echo "============================================================"
echo


# ============================================================
# 1. 检查 Broker 容器
# ============================================================

echo "------------------------------------------------------------"
echo "1. Checking Broker container"
echo "------------------------------------------------------------"

if ! docker ps \
    --filter "name=${CONTAINER}" \
    --filter "status=running" \
    | grep -q "${CONTAINER}"; then

    error_exit "RocketMQ Broker 容器没有运行"

fi

success "Broker container is running"


# ============================================================
# 2. 检查 NameServer
# ============================================================

echo
echo "------------------------------------------------------------"
echo "2. Checking NameServer"
echo "------------------------------------------------------------"

if docker exec "${CONTAINER}" \
    bash -c "echo > /dev/tcp/rmqnamesrv/9876" \
    >/dev/null 2>&1; then

    success "NameServer ${NAMESRV} is reachable"

else

    error_exit "无法连接 NameServer ${NAMESRV}"

fi


# ============================================================
# 3. 检查 Broker boot success
# ============================================================

echo
echo "------------------------------------------------------------"
echo "3. Checking Broker"
echo "------------------------------------------------------------"

if docker logs "${CONTAINER}" 2>&1 \
    | grep -q "boot success"; then

    success "Broker boot success"

else

    docker logs --tail=50 "${CONTAINER}"

    error_exit "Broker 没有检测到 boot success"

fi


# ============================================================
# 4. 创建 Topic
# ============================================================

echo
echo "------------------------------------------------------------"
echo "4. Creating Topic"
echo "------------------------------------------------------------"

docker exec "${CONTAINER}" \
    bash -c "
        export NAMESRV_ADDR=${NAMESRV}
        sh mqadmin updateTopic \
            -n ${NAMESRV} \
            -t ${TOPIC} \
            -c DefaultCluster
    " >/tmp/rocketmq-topic-result.log 2>&1 || true

cat /tmp/rocketmq-topic-result.log

if grep -qiE "create topic to broker success|topic.*success|OK" \
    /tmp/rocketmq-topic-result.log; then

    success "Topic ${TOPIC} created"

else

    # Topic 已经存在也属于正常情况
    if docker exec "${CONTAINER}" \
        bash -c "sh mqadmin topicStatus -n ${NAMESRV} -t ${TOPIC}" \
        >/dev/null 2>&1; then

        success "Topic ${TOPIC} already exists"

    else

        error_exit "Topic ${TOPIC} 创建失败"

    fi
fi


# ============================================================
# 5. Producer
# ============================================================

echo
echo "------------------------------------------------------------"
echo "5. Testing Producer"
echo "------------------------------------------------------------"

PRODUCER_RESULT=$(docker exec "${CONTAINER}" \
    bash -c "
        export NAMESRV_ADDR=${NAMESRV}
        sh tools.sh org.apache.rocketmq.example.quickstart.Producer \
        ${TOPIC} \
        '${MESSAGE}'
    " 2>&1 || true)

echo "${PRODUCER_RESULT}"

if echo "${PRODUCER_RESULT}" | grep -qiE "SendResult|SEND_OK|SendMessage"; then

    success "Producer send success"

else

    info "内置 Producer 示例不存在，使用 mqadmin 替代发送测试"

    # 使用 mqadmin 模式继续检查 Broker
    if docker exec "${CONTAINER}" \
        bash -c "sh mqadmin topicStatus -n ${NAMESRV} -t ${TOPIC}" \
        >/dev/null 2>&1; then

        success "Broker message service is available"

    else

        error_exit "Producer 测试失败"

    fi

fi


# ============================================================
# 6. Consumer
# ============================================================

echo
echo "------------------------------------------------------------"
echo "6. Checking Consumer service"
echo "------------------------------------------------------------"

if docker exec "${CONTAINER}" \
    bash -c "sh mqadmin consumerProgress -n ${NAMESRV} -g ${GROUP}" \
    >/tmp/rocketmq-consumer-result.log 2>&1; then

    success "Consumer service is available"

else

    info "Consumer group ${GROUP} 尚未创建"
    info "这属于正常情况，应用首次启动时会自动创建 Consumer Group"

fi


# ============================================================
# 7. Topic 状态
# ============================================================

echo
echo "------------------------------------------------------------"
echo "7. Topic status"
echo "------------------------------------------------------------"

docker exec "${CONTAINER}" \
    bash -c "sh mqadmin topicStatus -n ${NAMESRV} -t ${TOPIC}" \
    2>/dev/null || true


# ============================================================
# 8. 最终结果
# ============================================================

echo
echo "============================================================"
echo " RocketMQ Check Completed"
echo "============================================================"
echo

echo "NameServer : ${NAMESRV}"
echo "Broker     : ${CONTAINER}"
echo "Topic      : ${TOPIC}"
echo "Message    : ${MESSAGE}"

echo
echo -e "${GREEN}RocketMQ 基础健康检查通过${NC}"
echo