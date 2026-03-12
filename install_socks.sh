#!/bin/bash
#
# SOCKS5 Proxy Server (microsocks) 一键安装脚本
# 支持: CentOS 7/8, Ubuntu 18.04+, Debian 10+, Alpine 3.14+
# 用法: bash install_socks5.sh [端口] [用户名] [密码]
#

set -euo pipefail

# 默认配置
SOCKS5_PORT="${1:-1080}"
SOCKS5_USER="${2:-socks5}"
SOCKS5_PASS="${3:-}"
MICROSOCKS_BIN=""

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# 检查 root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 用户运行此脚本"
        exit 1
    fi
}

# 检测系统
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        log_error "无法检测操作系统"
        exit 1
    fi
    log_info "检测到系统: $OS $OS_VERSION"
}

# 生成随机密码（仅字母数字，避免特殊字符在命令行参数中引发问题）
generate_password() {
    if [[ -z "$SOCKS5_PASS" ]]; then
        SOCKS5_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
    fi
}

# 从源码编译安装 microsocks
install_microsocks_from_source() {
    local tmpdir
    tmpdir=$(mktemp -d)
    log_info "从源码编译 microsocks..."
    curl -sL "https://github.com/rofl0r/microsocks/archive/refs/heads/master.tar.gz" \
        -o "$tmpdir/microsocks.tar.gz"
    tar xzf "$tmpdir/microsocks.tar.gz" -C "$tmpdir"
    cd "$tmpdir/microsocks-master"
    make
    install -m 755 microsocks /usr/local/bin/microsocks
    cd /
    rm -rf "$tmpdir"
    MICROSOCKS_BIN="/usr/local/bin/microsocks"
    log_info "microsocks 编译安装完成: $MICROSOCKS_BIN"
}

# 安装 microsocks
install_microsocks() {
    case "$OS" in
        ubuntu|debian)
            apt-get update -qq
            if apt-get install -y -qq microsocks 2>/dev/null; then
                MICROSOCKS_BIN=$(command -v microsocks)
                log_info "microsocks 已通过 apt 安装"
            else
                log_warn "apt 中找不到 microsocks，改为从源码编译..."
                apt-get install -y -qq gcc make curl
                install_microsocks_from_source
            fi
            ;;
        centos|rhel|rocky|almalinux)
            yum install -y gcc make curl
            install_microsocks_from_source
            ;;
        alpine)
            apk update
            if apk add --no-cache microsocks 2>/dev/null; then
                MICROSOCKS_BIN=$(command -v microsocks)
                log_info "microsocks 已通过 apk 安装"
            else
                log_warn "apk 中找不到 microsocks，改为从源码编译..."
                apk add --no-cache gcc make curl musl-dev
                install_microsocks_from_source
            fi
            ;;
        *)
            log_error "不支持的系统: $OS"
            exit 1
            ;;
    esac
}

# 配置 systemd 服务
setup_service() {
    if [[ "$OS" == "alpine" ]]; then
        setup_openrc_service
        return
    fi

    cat > /etc/systemd/system/microsocks.service <<EOF
[Unit]
Description=MicroSOCKS SOCKS5 Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=${MICROSOCKS_BIN} -i 0.0.0.0 -p ${SOCKS5_PORT} -u ${SOCKS5_USER} -P ${SOCKS5_PASS}
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable microsocks
    systemctl restart microsocks
    log_info "服务 microsocks 已启动"
}

# Alpine OpenRC 服务
setup_openrc_service() {
    local init_script="/etc/init.d/microsocks"
    cat > "$init_script" <<EOF
#!/sbin/openrc-run

name="microsocks"
description="MicroSOCKS SOCKS5 Proxy Server"
command="${MICROSOCKS_BIN}"
command_args="-i 0.0.0.0 -p ${SOCKS5_PORT} -u ${SOCKS5_USER} -P ${SOCKS5_PASS}"
command_background=true
pidfile="/var/run/microsocks.pid"

depend() {
    need net
    after firewall
}
EOF

    chmod +x "$init_script"
    rc-update add microsocks default
    rc-service microsocks restart
    log_info "服务 microsocks 已启动 (OpenRC)"
}

# 配置防火墙
setup_firewall() {
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port="${SOCKS5_PORT}/tcp" 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        log_info "firewalld 已放行端口 ${SOCKS5_PORT}"
    elif command -v ufw &>/dev/null; then
        ufw allow "${SOCKS5_PORT}/tcp" 2>/dev/null || true
        log_info "ufw 已放行端口 ${SOCKS5_PORT}"
    fi

    if command -v iptables &>/dev/null; then
        iptables -C INPUT -p tcp --dport "${SOCKS5_PORT}" -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p tcp --dport "${SOCKS5_PORT}" -j ACCEPT 2>/dev/null || true
    fi
}

# 验证服务
verify() {
    sleep 2
    if ss -tlnp | grep -q ":${SOCKS5_PORT}"; then
        log_info "SOCKS5 代理服务运行正常"
    else
        if [[ "$OS" == "alpine" ]]; then
            log_error "服务未正常启动，请检查: rc-service microsocks status"
        else
            log_error "服务未正常启动，请检查: journalctl -u microsocks"
        fi
        exit 1
    fi
}

# 打印连接信息
print_info() {
    local server_ip
    server_ip=$(curl -s4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

    echo ""
    echo "=========================================="
    echo "  SOCKS5 代理安装完成"
    echo "=========================================="
    echo "  服务器地址: ${server_ip}"
    echo "  端口:       ${SOCKS5_PORT}"
    echo "  用户名:     ${SOCKS5_USER}"
    echo "  密码:       ${SOCKS5_PASS}"
    echo ""
    echo "  测试命令:"
    echo "  curl -x socks5://${SOCKS5_USER}:${SOCKS5_PASS}@${server_ip}:${SOCKS5_PORT} https://ifconfig.me"
    echo ""
    echo "  管理命令:"
    if [[ "$OS" == "alpine" ]]; then
        echo "  rc-service microsocks status"
        echo "  rc-service microsocks restart"
    else
        echo "  systemctl status microsocks"
        echo "  systemctl restart microsocks"
        echo "  journalctl -u microsocks -f"
    fi
    echo "=========================================="
}

# 卸载
uninstall() {
    log_warn "正在卸载 SOCKS5 代理..."
    rc-service microsocks stop 2>/dev/null || true
    rc-update del microsocks default 2>/dev/null || true
    rm -f /etc/init.d/microsocks
    systemctl stop microsocks 2>/dev/null || true
    systemctl disable microsocks 2>/dev/null || true
    rm -f /etc/systemd/system/microsocks.service
    systemctl daemon-reload 2>/dev/null || true
    log_info "卸载完成"
    exit 0
}

# 主流程
main() {
    if [[ "${1:-}" == "uninstall" ]]; then
        uninstall
    fi

    check_root
    detect_os
    generate_password
    log_info "开始安装 SOCKS5 代理 (端口: ${SOCKS5_PORT})..."
    install_microsocks
    setup_service
    setup_firewall
    verify
    print_info
}

main "$@"
