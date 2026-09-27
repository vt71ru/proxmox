#!/bin/sh

# ============================================================
# A2 — РЕЗЕРВНОЕ КОПИРОВАНИЕ GL.iNet FLINT 2 / OPENWRT
# Версия 1.1
#
# Назначение:
#   Создание резервной копии конфигурации OpenWrt
#   перед изменением сетевой архитектуры.
#
# Скрипт ТОЛЬКО ЧИТАЕТ и СОЗДАЁТ КОПИИ.
#
# НЕ выполняет:
#   - uci set
#   - uci delete
#   - uci commit
#   - service restart
#   - network restart
#   - reboot
#
# Изменения v1.1:
#   - Добавлена проверка внешнего IP
#   - Добавлено сохранение ключей WireGuard
#   - Добавлен статус служб dnsmasq и firewall
#
# ============================================================

set -u

DATE="$(date '+%Y-%m-%d_%H-%M-%S')"

BACKUP_DIR="/root/network-audit/A2_${DATE}"

mkdir -p "$BACKUP_DIR"


# ============================================================
# FUNCTIONS
# ============================================================

save_command()
{
    NAME="$1"
    COMMAND="$2"

    printf '%s\n' "# $COMMAND" > "$BACKUP_DIR/$NAME"

    sh -c "$COMMAND" >> "$BACKUP_DIR/$NAME" 2>&1 || true
}


copy_if_exists()
{
    SOURCE="$1"
    DEST="$2"

    if [ -f "$SOURCE" ]; then
        cp -a "$SOURCE" "$DEST"
        printf '[OK] %s\n' "$SOURCE"
    else
        printf '[SKIP] %s отсутствует\n' "$SOURCE"
    fi
}


# ============================================================
# START
# ============================================================

echo
echo "============================================================"
echo "A2 — РЕЗЕРВНОЕ КОПИРОВАНИЕ GL.iNet FLINT 2 / OPENWRT"
echo "============================================================"
echo
echo "Дата:       $(date)"
echo "Hostname:   $(uci -q get system.@system[0].hostname 2>/dev/null || hostname)"
echo "Backup dir: $BACKUP_DIR"
echo


# ============================================================
# 1. SYSUPGRADE BACKUP
# ============================================================

echo "[1] Создание полного sysupgrade backup"

SYSUPGRADE_BACKUP="$BACKUP_DIR/flint2-sysupgrade-backup.tar.gz"

if command -v sysupgrade >/dev/null 2>&1; then

    sysupgrade -b "$SYSUPGRADE_BACKUP"

    if [ -f "$SYSUPGRADE_BACKUP" ]; then
        echo "[OK] Sysupgrade backup создан."
    else
        echo "[ERROR] Sysupgrade backup не создан."
    fi

else

    echo "[ERROR] Команда sysupgrade отсутствует."

fi


# ============================================================
# 2. UCI EXPORT
# ============================================================

echo
echo "[2] Экспорт UCI configuration"

uci export network \
    > "$BACKUP_DIR/network.uci" \
    2>&1 || true

uci export dhcp \
    > "$BACKUP_DIR/dhcp.uci" \
    2>&1 || true

uci export firewall \
    > "$BACKUP_DIR/firewall.uci" \
    2>&1 || true

uci export system \
    > "$BACKUP_DIR/system.uci" \
    2>&1 || true


# ============================================================
# 3. RAW UCI CONFIGURATION
# ============================================================

echo
echo "[3] Сохранение полного UCI configuration"

save_command \
    uci-network.txt \
    "uci show network"

save_command \
    uci-dhcp.txt \
    "uci show dhcp"

save_command \
    uci-firewall.txt \
    "uci show firewall"

save_command \
    uci-system.txt \
    "uci show system"


# ============================================================
# 4. NETWORK STATE
# ============================================================

echo
echo "[4] Сохранение текущего состояния сети"

save_command \
    ip-addr.txt \
    "ip addr"

save_command \
    ip-link.txt \
    "ip link"

save_command \
    ip-route.txt \
    "ip route"

save_command \
    ip-route6.txt \
    "ip -6 route"

save_command \
    ip-rule.txt \
    "ip rule"

save_command \
    ip-neigh.txt \
    "ip neigh"


# ============================================================
# 5. BRIDGE / VLAN
# ============================================================

echo
echo "[5] Сохранение Bridge / VLAN"

if command -v bridge >/dev/null 2>&1; then

    save_command \
        bridge-link.txt \
        "bridge link"

    save_command \
        bridge-vlan.txt \
        "bridge vlan show"

else

    echo "bridge command отсутствует." \
        > "$BACKUP_DIR/bridge-status.txt"

fi


# ============================================================
# 6. DNS
# ============================================================

echo
echo "[6] Сохранение DNS"

copy_if_exists \
    /etc/resolv.conf \
    "$BACKUP_DIR/resolv.conf"

save_command \
    dnsmasq-process.txt \
    "ps w"

save_command \
    dns-sockets.txt \
    "ss -lntup"


# ============================================================
# 7. FIREWALL / NFTABLES
# ============================================================

echo
echo "[7] Сохранение текущего firewall"

if command -v nft >/dev/null 2>&1; then

    save_command \
        nft-ruleset.txt \
        "nft list ruleset"

    save_command \
        nft-tables.txt \
        "nft list tables"

    save_command \
        nft-counters.txt \
        "nft list counters"

else

    echo "nft отсутствует." \
        > "$BACKUP_DIR/nft-status.txt"

fi


# ============================================================
# 8. SYSTEM INFORMATION
# ============================================================

echo
echo "[8] Сохранение информации о системе"

save_command \
    system-board.txt \
    "ubus call system board"

copy_if_exists \
    /etc/openwrt_release \
    "$BACKUP_DIR/openwrt_release"

copy_if_exists \
    /etc/config/network \
    "$BACKUP_DIR/config-network"

copy_if_exists \
    /etc/config/dhcp \
    "$BACKUP_DIR/config-dhcp"

copy_if_exists \
    /etc/config/firewall \
    "$BACKUP_DIR/config-firewall"

copy_if_exists \
    /etc/config/system \
    "$BACKUP_DIR/config-system"


# ============================================================
# 9. IP FORWARDING
# ============================================================

echo
echo "[9] Сохранение IPv4 forwarding"

save_command \
    ip-forwarding.txt \
    "cat /proc/sys/net/ipv4/ip_forward"


# ============================================================
# 10. DHCP LEASES
# ============================================================

echo
echo "[10] Сохранение DHCP leases"

copy_if_exists \
    /tmp/dhcp.leases \
    "$BACKUP_DIR/dhcp.leases"


# ============================================================
# 11. EXTERNAL IP (DoT / CGNAT Check)
# ============================================================

echo
echo "[11] Сохранение внешнего IP (проверка белого адреса)"

save_command \
    external-ip.txt \
    "wget -qO- https://api.ipify.org 2>/dev/null || curl -sS https://ifconfig.me 2>/dev/null"


# ============================================================
# 12. WIREGUARD KEYS
# ============================================================

echo
echo "[12] Сохранение ключей WireGuard"

copy_if_exists \
    /etc/wireguard/server.key \
    "$BACKUP_DIR/server.key"

copy_if_exists \
    /etc/wireguard/server.pub \
    "$BACKUP_DIR/server.pub"


# ============================================================
# 13. SERVICE STATUS
# ============================================================

echo
echo "[13] Статус служб"

if [ -x /etc/init.d/dnsmasq ]; then
    save_command \
        service-dnsmasq.txt \
        "/etc/init.d/dnsmasq status"
else
    echo "dnsmasq init script not found." > "$BACKUP_DIR/service-dnsmasq.txt"
fi

if [ -x /etc/init.d/firewall ]; then
    save_command \
        service-firewall.txt \
        "/etc/init.d/firewall status"
else
    echo "firewall init script not found." > "$BACKUP_DIR/service-firewall.txt"
fi


# ============================================================
# 14. CREATE ARCHIVE
# ============================================================

echo
echo "[14] Создание общего архива"

ARCHIVE="/root/network-audit/A2_Flint2_${DATE}.tar.gz"

tar -czf "$ARCHIVE" \
    -C "/root/network-audit" \
    "A2_${DATE}" \
    2>/dev/null || true


# ============================================================
# 15. CHECK
# ============================================================

echo
echo "============================================================"
echo "A2 — РЕЗЕРВНОЕ КОПИРОВАНИЕ FLINT 2 ЗАВЕРШЕНО"
echo "============================================================"

echo
echo "Каталог:"
echo "$BACKUP_DIR"

echo
echo "Архив:"
echo "$ARCHIVE"

echo
echo "Размер каталога:"
du -sh "$BACKUP_DIR" 2>/dev/null || true

echo
echo "Размер архива:"
du -h "$ARCHIVE" 2>/dev/null || true

echo
echo "Файлы:"
find "$BACKUP_DIR" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort

echo
echo "============================================================"
