#!/bin/bash
#
# HTTP Proxy Server (tinyproxy) 一键安装脚本
# 支持: CentOS 7/8, Ubuntu 18.04+, Debian 10+, Alpine 3.14+
# 用法: bash install_http.sh [端口] [用户名] [密码]
#       bash install_http.sh uninstall
#
# 说明: 优先使用系统包；若系统包版本低于 1.10（不支持 BasicAuth），自动从源码编译
#

set -euo pipefail

# 默认配置
HTTP_PORT="${1:-8080}"
HTTP_USER="${2:-proxy}"
HTTP_PASS="${3:-}"
TINYPROXY_BIN=""

# 源码编译时使用的版本（固定版本 + sha256 校验）
TINYPROXY_SRC_VERSION="1.11.3"
TINYPROXY_SRC_SHA256="9bcf46db1a2375ff3e3d27a41982f1efec4706cce8899ff9f33323a8218f7592"

CONF_DIR="/etc/tinyproxy"
CONF_FILE="${CONF_DIR}/http-proxy.conf"
SERVICE_NAME="tinyproxy-http"

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

# 校验参数
validate_args() {
    if ! [[ "$HTTP_PORT" =~ ^[0-9]+$ ]] || (( HTTP_PORT < 1 || HTTP_PORT > 65535 )); then
        log_error "端口不合法: $HTTP_PORT"
        exit 1
    fi
}

# 生成随机密码（仅字母数字，避免特殊字符在配置文件中引发问题）
generate_password() {
    if [[ -z "$HTTP_PASS" ]]; then
        HTTP_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
    fi
    if ! [[ "$HTTP_USER" =~ ^[A-Za-z0-9_.-]+$ && "$HTTP_PASS" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        log_error "用户名和密码仅允许字母、数字及 _ . -"
        exit 1
    fi
}

# 版本比较: $1 >= $2 返回 0
version_ge() {
    local IFS=.
    local -a a=($1) b=($2)
    local i
    for i in 0 1 2; do
        local x=${a[i]:-0} y=${b[i]:-0}
        (( x > y )) && return 0
        (( x < y )) && return 1
    done
    return 0
}

# 检查 tinyproxy 版本是否支持 BasicAuth (>= 1.10)
tinyproxy_usable() {
    local bin ver
    bin=$(command -v tinyproxy 2>/dev/null) || return 1
    ver=$("$bin" -v 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)
    [[ -n "$ver" ]] && version_ge "$ver" "1.10" || return 1
    TINYPROXY_BIN="$bin"
    log_info "tinyproxy 版本: $ver"
}

# 从源码编译安装 tinyproxy
install_tinyproxy_from_source() {
    local tmpdir pkg="tinyproxy-${TINYPROXY_SRC_VERSION}.tar.gz"
    tmpdir=$(mktemp -d)
    log_info "从源码编译 tinyproxy ${TINYPROXY_SRC_VERSION}..."
    curl -fsSL "https://github.com/tinyproxy/tinyproxy/releases/download/${TINYPROXY_SRC_VERSION}/${pkg}" \
        -o "$tmpdir/$pkg"

    if [[ "$(sha256sum "$tmpdir/$pkg" | awk '{print $1}')" != "$TINYPROXY_SRC_SHA256" ]]; then
        rm -rf "$tmpdir"
        log_error "tinyproxy 源码包 sha256 校验失败"
        exit 1
    fi

    tar xzf "$tmpdir/$pkg" -C "$tmpdir"
    cd "$tmpdir/tinyproxy-${TINYPROXY_SRC_VERSION}"
    ./configure >/dev/null
    make >/dev/null
    install -m 755 src/tinyproxy /usr/local/bin/tinyproxy
    cd /
    rm -rf "$tmpdir"
    TINYPROXY_BIN="/usr/local/bin/tinyproxy"
    log_info "tinyproxy 编译安装完成: $TINYPROXY_BIN"
}

# 安装 tinyproxy
install_tinyproxy() {
    case "$OS" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y -qq curl iproute2
            apt-get install -y -qq tinyproxy 2>/dev/null || true
            if ! tinyproxy_usable; then
                log_warn "apt 中的 tinyproxy 不可用或版本过低，改为从源码编译..."
                apt-get install -y -qq gcc make
                install_tinyproxy_from_source
            fi
            ;;
        centos|rhel|rocky|almalinux)
            yum install -y epel-release 2>/dev/null || true
            yum install -y curl iproute
            yum install -y tinyproxy 2>/dev/null || true
            if ! tinyproxy_usable; then
                log_warn "yum 中的 tinyproxy 不可用或版本过低，改为从源码编译..."
                yum install -y gcc make
                install_tinyproxy_from_source
            fi
            ;;
        alpine)
            apk update
            apk add --no-cache curl iproute2
            apk add --no-cache tinyproxy 2>/dev/null || true
            if ! tinyproxy_usable; then
                log_warn "apk 中的 tinyproxy 不可用或版本过低，改为从源码编译..."
                apk add --no-cache gcc make musl-dev
                install_tinyproxy_from_source
            fi
            ;;
        *)
            log_error "不支持的系统: $OS"
            exit 1
            ;;
    esac

    # 停用系统包自带的默认实例，避免与本脚本的服务混淆
    systemctl disable --now tinyproxy 2>/dev/null || true
    rc-service tinyproxy stop 2>/dev/null || true
    rc-update del tinyproxy default 2>/dev/null || true
}

# 写入配置（凭据只放在 root 600 配置文件中，tinyproxy 读取配置后降权为 nobody 运行）
write_config() {
    mkdir -p "$CONF_DIR"
    cat > "$CONF_FILE" <<EOF
User nobody
Group $(id -gn nobody)
Port ${HTTP_PORT}
Timeout 600
MaxClients 512
BasicAuth ${HTTP_USER} ${HTTP_PASS}
DisableViaHeader Yes
LogLevel Warning
EOF
    chmod 600 "$CONF_FILE"
    log_info "配置文件已写入: $CONF_FILE"
}

# 配置 systemd 服务
setup_service() {
    if [[ "$OS" == "alpine" ]]; then
        setup_openrc_service
        return
    fi

    cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Tinyproxy HTTP Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=${TINYPROXY_BIN} -d -c ${CONF_FILE}
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME}
    systemctl restart ${SERVICE_NAME}
    log_info "服务 ${SERVICE_NAME} 已启动"
}

# Alpine OpenRC 服务
setup_openrc_service() {
    local init_script="/etc/init.d/${SERVICE_NAME}"
    cat > "$init_script" <<EOF
#!/sbin/openrc-run

name="${SERVICE_NAME}"
description="Tinyproxy HTTP Proxy Server"
command="${TINYPROXY_BIN}"
command_args="-d -c ${CONF_FILE}"
command_background=true
pidfile="/var/run/${SERVICE_NAME}.pid"

depend() {
    need net
    after firewall
}
EOF

    chmod +x "$init_script"
    rc-update add ${SERVICE_NAME} default
    rc-service ${SERVICE_NAME} restart
    log_info "服务 ${SERVICE_NAME} 已启动 (OpenRC)"
}

# 配置防火墙
setup_firewall() {
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port="${HTTP_PORT}/tcp" 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        log_info "firewalld 已放行端口 ${HTTP_PORT}"
    elif command -v ufw &>/dev/null; then
        ufw allow "${HTTP_PORT}/tcp" 2>/dev/null || true
        log_info "ufw 已放行端口 ${HTTP_PORT}"
    fi

    if command -v iptables &>/dev/null; then
        iptables -C INPUT -p tcp --dport "${HTTP_PORT}" -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p tcp --dport "${HTTP_PORT}" -j ACCEPT 2>/dev/null || true
    fi
    if command -v ip6tables &>/dev/null; then
        ip6tables -C INPUT -p tcp --dport "${HTTP_PORT}" -j ACCEPT 2>/dev/null || \
        ip6tables -I INPUT -p tcp --dport "${HTTP_PORT}" -j ACCEPT 2>/dev/null || true
    fi
}

# 验证服务
verify() {
    sleep 2
    if ss -tln | awk '{print $4}' | grep -qE ":${HTTP_PORT}\$"; then
        log_info "HTTP 代理服务运行正常"
    else
        if [[ "$OS" == "alpine" ]]; then
            log_error "服务未正常启动，请检查: rc-service ${SERVICE_NAME} status"
        else
            log_error "服务未正常启动，请检查: journalctl -u ${SERVICE_NAME}"
        fi
        exit 1
    fi
}

# 打印连接信息
print_info() {
    local server_ip
    server_ip=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

    echo ""
    echo "=========================================="
    echo "  HTTP 代理安装完成"
    echo "=========================================="
    echo "  服务器地址: ${server_ip}"
    echo "  端口:       ${HTTP_PORT}"
    echo "  用户名:     ${HTTP_USER}"
    echo "  密码:       ${HTTP_PASS}"
    echo ""
    echo "  测试命令:"
    echo "  curl -x http://${HTTP_USER}:${HTTP_PASS}@${server_ip}:${HTTP_PORT} https://ifconfig.me"
    echo ""
    echo "  注意: HTTP 代理认证为明文传输，账号密码可能被中间人截获"
    echo ""
    echo "  管理命令:"
    if [[ "$OS" == "alpine" ]]; then
        echo "  rc-service ${SERVICE_NAME} status"
        echo "  rc-service ${SERVICE_NAME} restart"
    else
        echo "  systemctl status ${SERVICE_NAME}"
        echo "  systemctl restart ${SERVICE_NAME}"
        echo "  journalctl -u ${SERVICE_NAME} -f"
    fi
    echo "  配置文件: ${CONF_FILE}"
    echo "=========================================="
}

# 卸载（系统包安装的 tinyproxy 保留，仅移除本脚本创建的服务、配置和源码编译的二进制）
uninstall() {
    check_root
    log_warn "正在卸载 HTTP 代理..."
    rc-service ${SERVICE_NAME} stop 2>/dev/null || true
    rc-update del ${SERVICE_NAME} default 2>/dev/null || true
    rm -f /etc/init.d/${SERVICE_NAME}
    systemctl stop ${SERVICE_NAME} 2>/dev/null || true
    systemctl disable ${SERVICE_NAME} 2>/dev/null || true
    rm -f /etc/systemd/system/${SERVICE_NAME}.service
    systemctl daemon-reload 2>/dev/null || true
    rm -f "$CONF_FILE" /usr/local/bin/tinyproxy
    log_info "卸载完成"
    exit 0
}

# 主流程
main() {
    if [[ "${1:-}" == "uninstall" ]]; then
        uninstall
    fi

    check_root
    validate_args
    detect_os
    generate_password
    log_info "开始安装 HTTP 代理 (端口: ${HTTP_PORT})..."
    install_tinyproxy
    write_config
    setup_service
    setup_firewall
    verify
    print_info
}

main "$@"
