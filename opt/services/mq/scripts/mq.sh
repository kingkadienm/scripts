#!/bin/bash

set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$BASE_DIR"

case "$1" in

    start)
        echo "启动 MQ 基础设施..."
        docker compose up -d
        ;;

    stop)
        echo "停止 MQ 基础设施..."
        docker compose stop
        ;;

    restart)
        echo "重启 MQ 基础设施..."
        docker compose restart
        ;;

    down)
        echo "停止并删除容器..."
        echo "注意：不会删除 Docker Volume"
        docker compose down
        ;;

    status)
        echo
        echo "=============================="
        echo " 服务状态"
        echo "=============================="
        docker compose ps

        echo
        echo "=============================="
        echo " Docker Volume"
        echo "=============================="
        docker volume ls | grep minimal_ || true
        ;;

    logs)
        if [ -z "$2" ]; then
            docker compose logs --tail=100 -f
        else
            docker compose logs --tail=100 -f "$2"
        fi
        ;;

    rocketmq)
        echo "=============================="
        echo " RocketMQ NameServer"
        echo "=============================="
        docker logs --tail=50 minimal_rmqnamesrv

        echo
        echo "=============================="
        echo " RocketMQ Broker"
        echo "=============================="
        docker logs --tail=100 minimal_rmqbroker
        ;;

    test)
        ./test-rocketmq.sh
        ;;
    backup)
        ./backup.sh
         ;;

    restore)
        if [ -z "$2" ]; then
            echo "Usage:"
            echo "  ./mq.sh restore <backup_directory>"
            exit 1
        fi

        ./restore.sh "$2"
        ;;

    init)
        ./init.sh
        ;;

    pull)
        docker compose pull
        ;;

    config)
        docker compose config
        ;;

    *)
        echo
        echo "MQ Infrastructure Management"
        echo
        echo "Usage:"
        echo
        echo "  ./mq.sh init       初始化并启动"
        echo "  ./mq.sh start      启动"
        echo "  ./mq.sh stop       停止"
        echo "  ./mq.sh restart    重启"
        echo "  ./mq.sh down       删除容器"
        echo "  ./mq.sh status     查看状态"
        echo "  ./mq.sh logs       查看全部日志"
        echo "  ./mq.sh logs kafka 查看 Kafka 日志"
        echo "  ./mq.sh logs rmqbroker 查看 RocketMQ Broker 日志"
        echo "  ./mq.sh rocketmq   查看 RocketMQ 日志"
        echo "  ./mq.sh test       测试 RocketMQ"
        echo "  ./mq.sh pull       拉取镜像"
        echo "  ./mq.sh config     查看 Compose 配置"
        echo "  ./mq.sh backup      创建备份"
        echo "  ./mq.sh restore     恢复备份"
        echo
        ;;

esac