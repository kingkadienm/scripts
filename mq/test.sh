#!/bin/bash

set -u

PASS=0
FAIL=0

green() {
    echo -e "\033[32m$1\033[0m"
}

red() {
    echo -e "\033[31m$1\033[0m"
}

yellow() {
    echo -e "\033[33m$1\033[0m"
}

ok() {
    green "✓ $1"
    PASS=$((PASS + 1))
}

fail() {
    red "✗ $1"
    FAIL=$((FAIL + 1))
}

check_container() {
    local name="$1"

    if docker inspect "$name" >/dev/null 2>&1 &&
       [ "$(docker inspect -f '{{.State.Running}}' "$name")" = "true" ]; then
        ok "$name 容器运行正常"
    else
        fail "$name 容器未运行"
    fi
}

check_tcp() {
    local name="$1"
    local host="$2"
    local port="$3"

    if timeout 3 bash -c "</dev/tcp/${host}/${port}" 2>/dev/null; then
        ok "$name ${host}:${port} TCP 正常"
    else
        fail "$name ${host}:${port} TCP 连接失败"
    fi
}

echo "============================================================"
echo "                    Infrastructure Test"
echo "============================================================"
echo

# ============================================================
# 1. Docker
# ============================================================

echo "1. Docker"
echo "------------------------------------------------------------"

if docker info >/dev/null 2>&1; then
    ok "Docker 正常"
else
    fail "Docker 不可用"
fi

echo

# ============================================================
# 2. Containers
# ============================================================

echo "2. Container Status"
echo "------------------------------------------------------------"

check_container minimal_pgvector
check_container minimal_es
check_container minimal_kafka
check_container minimal_rmqnamesrv
check_container minimal_rmqbroker

echo

# ============================================================
# 3. PostgreSQL
# ============================================================

echo "3. PostgreSQL + pgvector"
echo "------------------------------------------------------------"

if docker exec minimal_pgvector \
    pg_isready -U postgres >/dev/null 2>&1; then
    ok "PostgreSQL 可连接"
else
    fail "PostgreSQL 连接失败"
fi

if docker exec minimal_pgvector \
    psql -U postgres -d vector_db \
    -c "SELECT 1;" >/dev/null 2>&1; then
    ok "PostgreSQL vector_db 数据库正常"
else
    fail "vector_db 数据库不可用"
fi

if docker exec minimal_pgvector \
    psql -U postgres -d vector_db \
    -tAc "SELECT 1 FROM pg_extension WHERE extname='vector';" \
    | grep -q 1; then
    ok "pgvector 扩展已安装"
else
    fail "pgvector 扩展不存在"
fi

echo

# ============================================================
# 4. Elasticsearch
# ============================================================

echo "4. Elasticsearch"
echo "------------------------------------------------------------"

if curl -fs http://127.0.0.1:9200 >/dev/null 2>&1; then
    ok "Elasticsearch HTTP 正常"
else
    fail "Elasticsearch HTTP 连接失败"
fi

ES_STATUS=$(curl -fs http://127.0.0.1:9200/_cluster/health 2>/dev/null \
    | grep -o '"status":"[^"]*"' | head -1 || true)

if [ -n "$ES_STATUS" ]; then
    ok "Elasticsearch Cluster Health: $ES_STATUS"
else
    fail "Elasticsearch Cluster Health 获取失败"
fi

echo

# ============================================================
# 5. Kafka
# ============================================================

echo "5. Kafka"
echo "------------------------------------------------------------"

check_tcp "Kafka" 127.0.0.1 9092

echo
echo "Kafka Topic："

if docker exec minimal_kafka \
    /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server localhost:9092 \
    --list >/tmp/kafka_topics.txt 2>/dev/null; then

    ok "Kafka Admin API 正常"

    cat /tmp/kafka_topics.txt

else
    fail "Kafka Admin API 连接失败"
fi

echo

# ============================================================
# 6. Kafka Producer / Consumer
# ============================================================

echo "6. Kafka Producer / Consumer"
echo "------------------------------------------------------------"

KAFKA_TEST_TOPIC="TEST_TOPIC"

docker exec minimal_kafka \
    /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server localhost:9092 \
    --create \
    --if-not-exists \
    --topic "$KAFKA_TEST_TOPIC" \
    --partitions 1 \
    --replication-factor 1 >/dev/null 2>&1 || true

KAFKA_MESSAGE="hello-kafka-$(date +%s)"

echo "发送消息：$KAFKA_MESSAGE"

if echo "$KAFKA_MESSAGE" | docker exec -i minimal_kafka \
    /opt/kafka/bin/kafka-console-producer.sh \
    --bootstrap-server localhost:9092 \
    --topic "$KAFKA_TEST_TOPIC" >/dev/null 2>&1; then

    ok "Kafka Producer 发送成功"
else
    fail "Kafka Producer 发送失败"
fi

KAFKA_RESULT=$(docker exec minimal_kafka \
    /opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic "$KAFKA_TEST_TOPIC" \
    --from-beginning \
    --timeout-ms 5000 2>/dev/null \
    | grep "$KAFKA_MESSAGE" | head -1 || true)

if [ "$KAFKA_RESULT" = "$KAFKA_MESSAGE" ]; then
    ok "Kafka Consumer 收到消息"
else
    fail "Kafka Consumer 未收到测试消息"
fi

echo

# ============================================================
# 7. RocketMQ NameServer
# ============================================================

echo "7. RocketMQ NameServer"
echo "------------------------------------------------------------"

check_tcp "RocketMQ NameServer" 127.0.0.1 9876

echo

# ============================================================
# 8. RocketMQ Broker
# ============================================================

echo "8. RocketMQ Broker"
echo "------------------------------------------------------------"

check_tcp "RocketMQ Broker" 127.0.0.1 10911

if docker logs minimal_rmqbroker 2>&1 \
    | grep -q "boot success"; then
    ok "RocketMQ Broker 启动成功"
else
    fail "RocketMQ Broker 未检测到 boot success"
fi

echo

# ============================================================
# 9. RocketMQ Topic
# ============================================================

echo "9. RocketMQ Topic"
echo "------------------------------------------------------------"

RMQ_TOPIC="TEST_TOPIC"

if docker exec minimal_rmqbroker \
    sh mqadmin updateTopic \
    -n rmqnamesrv:9876 \
    -t "$RMQ_TOPIC" >/tmp/rmq_topic.log 2>&1; then

    ok "RocketMQ Topic 创建成功"

else

    if docker exec minimal_rmqbroker \
        sh mqadmin topicStatus \
        -n rmqnamesrv:9876 \
        -t "$RMQ_TOPIC" >/dev/null 2>&1; then

        ok "RocketMQ Topic 已存在"
    else
        fail "RocketMQ Topic 创建失败"
        cat /tmp/rmq_topic.log
    fi
fi

echo

# ============================================================
# 10. RocketMQ Broker 信息
# ============================================================

echo "10. RocketMQ Broker Info"
echo "------------------------------------------------------------"

if docker exec minimal_rmqbroker \
    sh mqadmin clusterList \
    -n rmqnamesrv:9876 >/tmp/rmq_cluster.log 2>&1; then

    ok "RocketMQ Cluster 查询成功"

    cat /tmp/rmq_cluster.log

else
    fail "RocketMQ Cluster 查询失败"
    cat /tmp/rmq_cluster.log
fi

echo

# ============================================================
# Summary
# ============================================================

echo "============================================================"
echo "                         Test Summary"
echo "============================================================"

echo
green "PASS: $PASS"
red "FAIL: $FAIL"
echo

if [ "$FAIL" -eq 0 ]; then
    green "所有基础设施测试通过 ✓"
    exit 0
else
    red "存在 $FAIL 个测试失败 ✗"
    exit 1
fi
