#!/bin/sh

# ============================================================
# A1 — ПЕРВИЧНАЯ ДИАГНОСТИКА OPENWRT / GL.iNet FLINT 2
# Версия 1.2
#
# Назначение:
#   Только чтение текущей конфигурации.
#
# Скрипт НЕ выполняет:
#   - uci set
#   - uci delete
#   - uci commit
#   - service restart
#   - /etc/init.d/network restart
#   - reboot
#
# Совместимость:
#   OpenWrt 25.x
#
# Особенности:
#   - не требует отдельной команды hostname
#   - корректно работает при отсутствии bridge
#   - использует UCI/sysfs как fallback
#   - сохраняет полный отчёт в /root/network-audit
#
# ============================================================

set -u


# ============================================================
# BASIC VARIABLES
# ============================================================

DATE="$(date '+%Y-%m-%d_%H-%M-%S')"

HOST="$(uci -q get system.@system[0].hostname 2>/dev/null || true)"

if [ -z "$HOST" ]; then
    HOST="$(uname -n 2>/dev/null || true)"
fi

if [ -z "$HOST" ]; then
    HOST="OpenWrt"
fi

OUTDIR="/root/network-audit"
OUTFILE="${OUTDIR}/A1_${HOST}_${DATE}.txt"

mkdir -p "$OUTDIR"


# ============================================================
# FUNCTIONS
# ============================================================

section()
{
    printf '\n\n'
    printf '%s\n' '============================================================'
    printf '%s\n' "$1"
    printf '%s\n' '============================================================'
}


run_cmd()
{
    printf '\n# %s\n' "$1"
    sh -c "$1" 2>&1
}


# ============================================================
# START
# ============================================================

{
    section "A1 — ПЕРВИЧНАЯ ДИАГНОСТИКА OPENWRT"

    printf 'Дата: %s\n' "$(date)"
    printf 'Hostname: %s\n' "$HOST"
    printf 'Отчёт: %s\n' "$OUTFILE"


    # ========================================================
    # 1. INTERFACES
    # ========================================================

    section "1. СЕТЕВЫЕ ИНТЕРФЕЙСЫ"

    run_cmd "ip link"


    # ========================================================
    # 2. IP ADDRESSES
    # ========================================================

    section "2. IP-АДРЕСА"

    run_cmd "ip addr"


    # ========================================================
    # 3. IPv4 ADDRESSES
    # ========================================================

    section "3. IPv4-АДРЕСА"

    run_cmd "ip -f inet addr"


    # ========================================================
    # 4. ROUTES
    # ========================================================

    section "4. МАРШРУТИЗАЦИЯ"

    run_cmd "ip route"


    # ========================================================
    # 5. POLICY ROUTING
    # ========================================================

    section "5. POLICY ROUTING"

    run_cmd "ip rule"


    # ========================================================
    # 6. BRIDGE
    # ========================================================

    section "6. BRIDGE"

    if command -v bridge >/dev/null 2>&1; then

        printf '\nКоманда bridge найдена.\n'

        run_cmd "bridge link"

    else

        printf '\nКоманда bridge НЕ установлена.\n'
        printf 'Используем альтернативную диагностику bridge.\n'

        printf '\n# /sys/class/net\n'
        ls -la /sys/class/net 2>&1

        printf '\n# br-lan information\n'

        if [ -d /sys/class/net/br-lan ]; then

            printf '\nbr-lan:\n'

            printf 'Operational state:\n'
            cat /sys/class/net/br-lan/operstate 2>/dev/null || true

            printf 'MTU:\n'
            cat /sys/class/net/br-lan/mtu 2>/dev/null || true

            printf '\nBridge ports:\n'
            ls -1 /sys/class/net/br-lan/brif 2>/dev/null || true

        else

            printf 'br-lan отсутствует.\n'

        fi

    fi


    # ========================================================
    # 7. VLAN
    # ========================================================

    section "7. VLAN"

    if command -v bridge >/dev/null 2>&1; then

        run_cmd "bridge vlan show"

    else

        printf '\nКоманда bridge отсутствует.\n'
        printf 'Проверяем VLAN через UCI и sysfs.\n'

        printf '\n# UCI VLAN-related configuration\n'

        uci show network 2>/dev/null \
            | grep -Ei 'vlan|bridge|ports|device' || true

        printf '\n# /sys/class/net VLAN devices\n'

        find /sys/class/net -maxdepth 1 -type l \
            -printf '%f\n' 2>/dev/null \
            | sort

    fi


    # ========================================================
    # 8. UCI NETWORK
    # ========================================================

    section "8. UCI NETWORK"

    run_cmd "uci show network"


    # ========================================================
    # 9. UCI DHCP
    # ========================================================

    section "9. UCI DHCP"

    run_cmd "uci show dhcp"


    # ========================================================
    # 10. UCI FIREWALL
    # ========================================================

    section "10. UCI FIREWALL"

    run_cmd "uci show firewall"


    # ========================================================
    # 11. SYSTEM
    # ========================================================

    section "11. SYSTEM BOARD"

    run_cmd "ubus call system board"


    # ========================================================
    # 12. WAN STATUS
    # ========================================================

    section "12. WAN STATUS"

    run_cmd "ubus call network.interface.wan status"


    # ========================================================
    # 13. IFSTATUS WAN
    # ========================================================

    section "13. IFSTATUS WAN"

    if command -v ifstatus >/dev/null 2>&1; then

        run_cmd "ifstatus wan"

    else

        printf 'Команда ifstatus отсутствует.\n'

    fi


    # ========================================================
    # 14. WAN UCI CONFIG
    # ========================================================

    section "14. WAN UCI"

    printf '\nWAN device:\n'
    uci -q get network.wan.device 2>/dev/null || true

    printf '\nWAN protocol:\n'
    uci -q get network.wan.proto 2>/dev/null || true

    printf '\nWAN IPv6:\n'
    uci -q get network.wan.ipv6 2>/dev/null || true


    # ========================================================
    # 15. WAN INTERFACE DETAILS
    # ========================================================

    section "15. WAN — ETH1"

    if ip link show dev eth1 >/dev/null 2>&1; then

        run_cmd "ip addr show dev eth1"

        printf '\nLink state:\n'
        cat /sys/class/net/eth1/operstate 2>/dev/null || true

        printf '\nMTU:\n'
        cat /sys/class/net/eth1/mtu 2>/dev/null || true

        printf '\nMAC:\n'
        cat /sys/class/net/eth1/address 2>/dev/null || true

    else

        printf 'Интерфейс eth1 отсутствует.\n'

    fi


    # ========================================================
    # 16. LAN BRIDGE DETAILS
    # ========================================================

    section "16. LAN BRIDGE — BR-LAN"

    if ip link show dev br-lan >/dev/null 2>&1; then

        run_cmd "ip addr show dev br-lan"

        printf '\nBridge ports:\n'
        ls -1 /sys/class/net/br-lan/brif 2>/dev/null || true

    else

        printf 'Интерфейс br-lan отсутствует.\n'

    fi


    # ========================================================
    # 17. DHCP CONFIGURATION SUMMARY
    # ========================================================

    section "17. DHCP SUMMARY"

    printf '\nLAN DHCP interface:\n'
    uci -q get dhcp.lan.interface 2>/dev/null || true

    printf '\nDHCP start:\n'
    uci -q get dhcp.lan.start 2>/dev/null || true

    printf '\nDHCP limit:\n'
    uci -q get dhcp.lan.limit 2>/dev/null || true

    printf '\nDHCP lease time:\n'
    uci -q get dhcp.lan.leasetime 2>/dev/null || true


    # ========================================================
    # 18. DNS
    # ========================================================

    section "18. DNS"

    if [ -f /etc/resolv.conf ]; then

        run_cmd "cat /etc/resolv.conf"

    else

        printf '/etc/resolv.conf отсутствует.\n'

    fi


    # ========================================================
    # 19. DNSMASQ
    # ========================================================

    section "19. DNSMASQ"

    if pidof dnsmasq >/dev/null 2>&1; then

        printf 'dnsmasq: RUNNING\n'

        printf 'PID:\n'
        pidof dnsmasq

    else

        printf 'dnsmasq: NOT RUNNING\n'

    fi


    # ========================================================
    # 20. FIREWALL SERVICE
    # ========================================================

    section "20. FIREWALL SERVICE"

    if [ -x /etc/init.d/firewall ]; then

        /etc/init.d/firewall status 2>&1 || true

    else

        printf '/etc/init.d/firewall отсутствует.\n'

    fi


    # ========================================================
    # 21. NAT / NFTABLES
    # ========================================================

    section "21. FIREWALL / NFTABLES"

    if command -v nft >/dev/null 2>&1; then

        run_cmd "nft list ruleset"

    else

        printf 'nft отсутствует.\n'

    fi


    # ========================================================
    # 22. DHCP LEASES
    # ========================================================

    section "22. DHCP LEASES"

    if [ -f /tmp/dhcp.leases ]; then

        run_cmd "cat /tmp/dhcp.leases"

    else

        printf '/tmp/dhcp.leases отсутствует.\n'

    fi


    # ========================================================
    # 23. NEIGHBOURS
    # ========================================================

    section "23. ARP / NEIGHBOURS"

    run_cmd "ip neigh"


    # ========================================================
    # 24. LISTENING SOCKETS
    # ========================================================

    section "24. ПРОСЛУШИВАЕМЫЕ ПОРТЫ"

    if command -v ss >/dev/null 2>&1; then

        run_cmd "ss -lntup"

    elif command -v netstat >/dev/null 2>&1; then

        run_cmd "netstat -lntup"

    else

        printf 'ss и netstat отсутствуют.\n'

    fi


    # ========================================================
    # 25. CURRENT CONFIG FILES
    # ========================================================

    section "25. ОСНОВНЫЕ CONFIG FILES"

    printf '\n/etc/config/network:\n'

    if [ -f /etc/config/network ]; then
        cat /etc/config/network
    else
        printf '/etc/config/network отсутствует.\n'
    fi


    printf '\n/etc/config/dhcp:\n'

    if [ -f /etc/config/dhcp ]; then
        cat /etc/config/dhcp
    else
        printf '/etc/config/dhcp отсутствует.\n'
    fi


    printf '\n/etc/config/firewall:\n'

    if [ -f /etc/config/firewall ]; then
        cat /etc/config/firewall
    else
        printf '/etc/config/firewall отсутствует.\n'
    fi


    # ========================================================
    # 26. FINAL SUMMARY
    # ========================================================

    section "26. ИТОГОВАЯ СВОДКА"

    printf '\nHostname:\n'
    printf '%s\n' "$HOST"


    printf '\nModel:\n'

    ubus call system board 2>/dev/null \
        | grep '"model"' || true


    printf '\nOpenWrt:\n'

    ubus call system board 2>/dev/null \
        | grep '"description"' || true


    printf '\nWAN device:\n'

    uci -q get network.wan.device 2>/dev/null || true


    printf '\nWAN protocol:\n'

    uci -q get network.wan.proto 2>/dev/null || true


    printf '\nWAN IPv4:\n'

    if command -v ifstatus >/dev/null 2>&1; then

        ifstatus wan 2>/dev/null \
            | grep -A3 '"ipv4-address"' || true

    else

        printf 'ifstatus отсутствует.\n'

    fi


    printf '\nDefault route:\n'

    ip route | grep '^default' || true


    printf '\nLAN address:\n'

    uci -q get network.lan.ipaddr 2>/dev/null || true


    printf '\nLAN device:\n'

    uci -q get network.lan.device 2>/dev/null || true


    printf '\nLAN bridge ports:\n'

    if [ -d /sys/class/net/br-lan/brif ]; then

        ls -1 /sys/class/net/br-lan/brif 2>/dev/null || true

    else

        printf 'br-lan отсутствует.\n'

    fi


    # ========================================================
    # END
    # ========================================================

    section "A1 — КОНЕЦ ОТЧЁТА"

    printf 'Отчёт сохранён:\n'
    printf '%s\n' "$OUTFILE"

} 2>&1 | tee "$OUTFILE"


printf '\n'
printf '%s\n' '============================================================'
printf 'A1 завершён.'
printf '\n'
printf 'Отчёт: %s\n' "$OUTFILE"
printf '%s\n' '============================================================'
