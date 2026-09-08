#!/bin/bash
set -e

echo "========== Mihomo 一键部署脚本 =========="

# ========== 请修改以下配置 ==========
SUB_URL="你的订阅地址"  # 填入你完整的原始订阅 URL
# ======================================

# 1. 安装 mihomo
echo "[1/7] 安装 Mihomo 内核..."
cd /tmp
sudo curl -L --connect-timeout 15 --max-time 120 \
  -o mihomo-linux-amd64-v3-v1.19.30.gz \
  "https://gh-proxy.com/https://github.com/MetaCubeX/mihomo/releases/download/v1.19.30/mihomo-linux-amd64-v3-v1.19.30.gz"
gunzip -f mihomo-linux-amd64-v3-v1.19.30.gz
chmod +x mihomo-linux-amd64-v3-v1.19.30
sudo mv mihomo-linux-amd64-v3-v1.19.30 /usr/local/bin/mihomo
echo "Mihomo 版本: $(mihomo -v | head -1)"

# 2. 创建目录
echo "[2/7] 创建配置目录..."
sudo mkdir -p /etc/mihomo

# 3. 下载 Geo 数据
echo "[3/7] 下载 Geo 数据文件..."
cd /etc/mihomo
echo "  下载 geoip.metadb..."
sudo curl -L --connect-timeout 15 --max-time 120 -o geoip.metadb \
  "https://gh-proxy.com/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb"
echo "  下载 geosite.dat..."
sudo curl -L --connect-timeout 15 --max-time 120 -o geosite.dat \
  "https://gh-proxy.com/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"

# 4. 下载订阅配置（对应第三节逻辑）
echo "[4/7] 下载订阅配置..."
FULL_SUB_URL="https://api.v1.mk/sub?target=clash&url=${SUB_URL}"

curl -s -o /tmp/config_temp.yaml "$FULL_SUB_URL"

if grep -q "proxies:" /tmp/config_temp.yaml; then
    echo "✅ 订阅配置文件下载成功！"
else
    echo "❌ 订阅转换失败，请检查转换接口或订阅链接。"
    rm -f /tmp/config_temp.yaml
    exit 1
fi

# 5. 生成自定义顶层配置并与订阅合并
echo "[5/7] 合并 TUN 和 Dashboard 配置..."
sudo tee /tmp/custom_head.yaml > /dev/null << 'CUSTOM'
# ------------------ 基础通用配置 ------------------
port: 7890
socks-port: 7891
allow-lan: true
bind-address: "*"
mode: Rule
log-level: info
ipv6: false

# Web 控制台接口
external-controller: 0.0.0.0:9090
secret: ""

# ------------------ TUN 模式核心设置 ------------------
tun:
  enable: true
  stack: system
  dns-hijack:
    - 'any:53'
  auto-route: false
  auto-detect-interface: true

# ------------------ 内建 DNS 设置 ------------------
dns:
  enable: true
  ipv6: false
  listen: 0.0.0.0:53
  fake-ip-range: 198.18.0.1/16
  use-hosts: true
  fake-ip-filter:
    - "*.lan"
    - "*.local"
    - "*.arpa"
    - time.*.com
    - ntp.*.com
    - +.market.xiaomi.com
    - localhost.ptlogin2.qq.com
    - "*.msftncsi.com"
    - www.msftconnecttest.com
  default-nameserver:
    - 119.29.29.29
    - 223.5.5.5
  nameserver:
    - 119.29.29.29
    - 223.5.5.5
  nameserver-policy:
    'geosite:cn':
      - 119.29.29.29
      - 223.5.5.5
    'geosite:geolocation-!cn':
      - tls://1.0.0.1:853
      - tls://dns.google:853
  proxy-server-nameserver:
    - 119.29.29.29
    - 223.5.5.5
  fallback:
    - 8.8.8.8
    - 1.1.1.1
    - tls://1.0.0.1:853
    - tls://dns.google:853
  fallback-filter:
    geoip: true
    geoip-code: CN
    geosite:
      - gfw
    ipcidr:
      - 240.0.0.0/4
CUSTOM

# 使用 Python 合并 Head 配置与订阅的 Proxies 节点配置
sudo python3 -c '
with open("/tmp/custom_head.yaml", "r") as f:
    head = f.read()

with open("/tmp/config_temp.yaml", "r") as f:
    sub = f.read()

import re
sub_match = re.search(r"(proxies:.*)", sub, re.DOTALL)
proxies_block = sub_match.group(1) if sub_match else ""

with open("/etc/mihomo/config.yaml", "w") as f:
    f.write(head + "\n" + proxies_block)
'
rm -f /tmp/custom_head.yaml /tmp/config_temp.yaml

# 6. 部署 Dashboard (Metacubexd)
echo "[6/7] 部署 Metacubexd Dashboard..."
cd /tmp
sudo rm -rf /tmp/metacubexd
git clone https://gh-proxy.com/https://github.com/metacubex/metacubexd.git -b gh-pages /tmp/metacubexd
sudo mkdir -p /etc/mihomo/ui
sudo cp -r /tmp/metacubexd/* /etc/mihomo/ui/
rm -rf /tmp/metacubexd

# 7. 创建 Systemd 服务并启动
echo "[7/7] 配置并启动 Systemd 服务..."
sudo tee /etc/systemd/system/mihomo.service > /dev/null << 'EOF'
[Unit]
Description=Mihomo Daemon, A rule based proxy in Go.
After=network.target network-online.target nss-lookup.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/mihomo
ExecStart=/usr/local/bin/mihomo -d /etc/mihomo
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now mihomo

# 8. 配置自动更新脚本
echo "========== 配置自动更新脚本 =========="
sudo tee /etc/mihomo/update_sub.sh > /dev/null << SCRIPT
#!/bin/bash
SUB_URL="${FULL_SUB_URL}"
CONFIG_PATH="/etc/mihomo/config.yaml"
TEMP_PATH="/tmp/config_temp.yaml"

curl -s -o "\$TEMP_PATH" "\$SUB_URL"

if [ \$? -ne 0 ] || [ ! -s "\$TEMP_PATH" ]; then
    echo "[\$(date)] 订阅下载失败，保持现有配置不变。" >> /var/log/mihomo_update.log
    exit 1
fi

if ! grep -q "proxies:" "\$TEMP_PATH"; then
    echo "[\$(date)] 订阅解析失败（未检测到 proxies 字段），已取消更新。" >> /var/log/mihomo_update.log
    rm -f "\$TEMP_PATH"
    exit 1
fi

# 恢复顶部配置合并
python3 -c '
import re
with open("/etc/mihomo/config.yaml", "r") as f:
    old_cfg = f.read()

# 提取原有顶层的自定义配置 (proxies 之前的部分)
head_match = re.search(r"^(.*?)(?=proxies:|\Z)", old_cfg, re.DOTALL)
head = head_match.group(1) if head_match else ""

with open("/tmp/config_temp.yaml", "r") as f:
    sub = f.read()

sub_match = re.search(r"(proxies:.*)", sub, re.DOTALL)
proxies_block = sub_match.group(1) if sub_match else ""

with open("/tmp/merged_config.yaml", "w") as f:
    f.write(head + "\n" + proxies_block)
'

# 语法测试
/usr/local/bin/mihomo -t -d /etc/mihomo -f /tmp/merged_config.yaml
if [ \$? -eq 0 ]; then
    mv /tmp/merged_config.yaml "\$CONFIG_PATH"
    systemctl restart mihomo
    echo "[\$(date)] 订阅配置更新成功并已重启 Mihomo 服务。" >> /var/log/mihomo_update.log
else
    echo "[\$(date)] 配置语法测试失败，已取消更新。" >> /var/log/mihomo_update.log
fi

rm -f "\$TEMP_PATH" /tmp/merged_config.yaml
SCRIPT

sudo chmod +x /etc/mihomo/update_sub.sh

# 配置定时任务 (每天凌晨 3:00)
(sudo crontab -l 2>/dev/null | grep -v "update_sub.sh"; echo "0 3 * * * /bin/bash /etc/mihomo/update_sub.sh >/dev/null 2>&1") | sudo crontab -

echo ""
echo "========== 部署完成 =========="
echo "验证提示："
echo "  1. 检查服务运行状态: sudo systemctl status mihomo"
echo "  2. 检查 TUN 网卡状态: ip addr show Meta"
echo "  3. 访问 Dashboard:    http://$(curl -s ifconfig.me):9090/ui/"
