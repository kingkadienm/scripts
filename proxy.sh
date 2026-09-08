cat << 'EOF' >> ~/.bash_profile

# ------------------ Clash/Mihomo 代理一键开关 ------------------
function proxy_on() {
    export http_proxy="http://127.0.0.1:7890"
    export https_proxy="http://127.0.0.1:7890"
    export all_proxy="socks5://127.0.0.1:7891"
    
    # 配置 Git 走代理
    git config --global http.proxy http://127.0.0.1:7890
    git config --global https.proxy http://127.0.0.1:7890
    
    echo "✅ 代理已开启 (HTTP: 7890 | SOCKS5: 7891 | Git 代理已生效)"
}

function proxy_off() {
    unset http_proxy https_proxy all_proxy
    
    # 取消 Git 代理
    git config --global --unset http.proxy
    git config --global --unset https.proxy
    
    echo "❌ 代理已关闭 (环境变量与 Git 代理已清除)"
}

function proxy_status() {
    echo "=== 终端环境变量 ==="
    echo "http_proxy  : $http_proxy"
    echo "https_proxy : $https_proxy"
    echo "all_proxy   : $all_proxy"
    echo "=== Git 代理配置 ==="
    echo "git http    : $(git config --global http.proxy)"
    echo "git https   : $(git config --global https.proxy)"
}

# 快捷别名
alias proxy_on="proxy_on"
alias proxy_off="proxy_off"
alias proxy_status="proxy_status"
EOF

# 使配置立即在当前终端生效
source ~/.bash_profile

echo "🎉 代理配置已成功写入 ~/.bash_profile 并已重载生效！"
