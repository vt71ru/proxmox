#!/bin/sh

# ============================================================
# A1 — ПЕРВИЧНАЯ ДИАГНОСТИКА OPENWRT / GL.iNet FLINT 2
# Версия 1.4
#
# Назначение:
#   Полностью диагностический скрипт.
#   Скрипт только ЧИТАЕТ текущую конфигурацию.
#
# Скрипт НЕ выполняет:
#   - uci set
#   - uci delete
#   - uci add
#   - uci commit
#   - service restart
#   - /etc/init.d/* restart
#   - /etc/init.d/* reload
#   - ifup / ifdown
#   - ip addr add/del
#   - ip route add/del
#   - nft add/delete/flush
#   - reboot
#
# Проверяет:
#   - сетевые интерфейсы
#   - IP-адреса
#   - маршрутизацию
#   - policy routing
#   - bridge / DSA
#   - VLAN
#   - UCI network
#   - UCI DHCP
#   - UCI firewall
#   - system board
#   - WAN status
#   - LAN status
#   - IPv4 forwarding
#   - DNS
#   - dnsmasq
#   - DNS resolver policy
#   - DoT/forwarding-related settings
#   - firewall service
#   - nftables rules
#   - nftables counters
#   - NAT
#   - DHCP leases
#   - ARP/neighbours
#   - listening sockets
#   - основные конфигурационные файлы
#   - итоговую сводку
#
# Совместимость:
#   OpenWrt 25.x
#
# Особенности:
#   - не требует отдельной команды hostname
#   - не предполагает конкретное имя WAN-интерфейса
#   - не предполагает eth1 как WAN
#   - учитывает DSA
#   - корректно работает при отсутствии bridge
#   - использует UCI/sysfs как fallback
#   - сохраняет полный отчёт в /root/network-audit
#
# ============================================================

set -u


# ============================================================
# 1. BASIC VARIABLES
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
# 2. FUNCTIONS
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
    sh -c "$1" 2>&1 || true
}


uci_get()
{
    uci -q get "$1" 2>/dev/null || true
}


command_exists()
{
    command -v "$1" >/dev/null 2>&1
}


# ============================================================
# 3. START
# ============================================================

{
    section "A1 — ПЕРВИЧНАЯ ДИАГНОСТИКА OPENWRT"

    printf 'Дата запуска: %s\n' "$(date)"
    printf 'Hostname: %s\n' "$HOST"
    printf 'Отчёт: %s\n' "$OUTFILE"


    # ========================================================
    # 4. SYSTEM INFORMATION
    # ========================================================

    section "4. SYSTEM INFORMATION"

    run_cmd "uname -a"

    printf '\nOpenWrt release:\n'

    if [ -f /etc/openwrt_release ]; then
        cat /etc/openwrt_release
    else
        printf '/etc/openwrt_release отсутствует.\n'
    fi

    printf '\nBoard information:\n'

    if command_exists ubus; then
        run_cmd "ubus call system board"
    else
        printf 'ubus отсутствует.\n'
    fi


    # ========================================================
    # 5. INTERFACES
    # ========================================================

    section "5. СЕТЕВЫЕ ИНТЕРФЕЙСЫ"

    run_cmd "ip link"

    printf '\nСписок /sys/class/net:\n'
    ls -la /sys/class/net 2>&1 || true


    # ========================================================
    # 6. IP ADDRESSES
    # ========================================================

    section "6. IP-АДРЕСА"

    run_cmd "ip addr"


    # ========================================================
    # 7. IPv4 ADDRESSES
    # ========================================================

    section "7. IPv4-АДРЕСА"

    run_cmd "ip -f inet addr"


    # ========================================================
    # 8. IPv6 ADDRESSES
    # ========================================================

    section "8. IPv6-АДРЕСА"

    run_cmd "ip -f inet6 addr"


    # ========================================================
    # 9. ROUTES
    # ========================================================

    section "9. МАРШРУТИЗАЦИЯ"

    run_cmd "ip route"

    printf '\nDefault route:\n'
    ip route 2>/dev/null | grep '^default' || true


    # ========================================================
    # 10. IPv6 ROUTES
    # ========================================================

    section "10. IPv6 ROUTING"

    run_cmd "ip -6 route"


    # ========================================================
    # 11. POLICY ROUTING
    # ========================================================

    section "11. POLICY ROUTING"

    run_cmd "ip rule"

    printf '\nIPv4 route tables:\n'
    run_cmd "ip route show table all"


    # ========================================================
    # 12. IP FORWARDING
    # ========================================================

    section "12. IPv4 FORWARDING"

    if [ -f /proc/sys/net/ipv4/ip_forward ]; then

        printf 'IPv4 forwarding:\n'
        cat /proc/sys/net/ipv4/ip_forward

        printf '\nРасшифровка:\n'

        FORWARDING="$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || printf 'unknown')"

        case "$FORWARDING" in
            1)
                printf 'ENABLED — маршрутизация IPv4 разрешена.\n'
                ;;
            0)
                printf 'DISABLED — маршрутизация IPv4 отключена.\n'
                ;;
            *)
                printf 'UNKNOWN.\n'
                ;;
        esac

    else

        printf '/proc/sys/net/ipv4/ip_forward отсутствует.\n'

    fi


    # ========================================================
    # 13. BRIDGE
    # ========================================================

    section "13. BRIDGE"

    if command_exists bridge; then

        printf '\nКоманда bridge найдена.\n'

        run_cmd "bridge link"

        printf '\nBridge VLAN information:\n'
        run_cmd "bridge vlan show"

    else

        printf '\nКоманда bridge НЕ установлена.\n'
        printf 'Используем альтернативную диагностику bridge.\n'

        printf '\n# /sys/class/net\n'
        ls -la /sys/class/net 2>&1 || true

    fi


    # ========================================================
    # 14. BRIDGE DEVICES
    # ========================================================

    section "14. BRIDGE DEVICES"

    printf '\nОбнаруженные bridge-интерфейсы:\n'

    for DEV in /sys/class/net/*; do

        [ -e "$DEV" ] || continue

        NAME="$(basename "$DEV")"

        if [ -d "$DEV/bridge" ]; then

            printf '\nBridge: %s\n' "$NAME"

            printf 'State:\n'
            cat "$DEV/operstate" 2>/dev/null || true

            printf 'MTU:\n'
            cat "$DEV/mtu" 2>/dev/null || true

            printf 'MAC:\n'
            cat "$DEV/address" 2>/dev/null || true

            printf 'Ports:\n'
            ls -1 "$DEV/brif" 2>/dev/null || true

        fi

    done


    # ========================================================
    # 15. BR-LAN
    # ========================================================

    section "15. BR-LAN"

    if ip link show dev br-lan >/dev/null 2>&1; then

        printf 'br-lan найден.\n'

        run_cmd "ip addr show dev br-lan"

        printf '\nBridge ports:\n'
        ls -1 /sys/class/net/br-lan/brif 2>/dev/null || true

        printf '\nOperational state:\n'
        cat /sys/class/net/br-lan/operstate 2>/dev/null || true

        printf '\nMTU:\n'
        cat /sys/class/net/br-lan/mtu 2>/dev/null || true

        printf '\nMAC:\n'
        cat /sys/class/net/br-lan/address 2>/dev/null || true

    else

        printf 'Интерфейс br-lan отсутствует.\n'

    fi


    # ========================================================
    # 16. VLAN / DSA
    # ========================================================

    section "16. VLAN / DSA"

    printf '\nUCI network VLAN/bridge/device configuration:\n'

    uci show network 2>/dev/null \
        | grep -Ei 'vlan|bridge|ports|device|tagged|untagged' || true

    printf '\nLinux network devices:\n'

    for DEV in /sys/class/net/*; do

        [ -e "$DEV" ] || continue

        NAME="$(basename "$DEV")"

        printf '%s' "$NAME"

        if [ -L "$DEV/master" ]; then
            printf ' -> master='
            basename "$(readlink "$DEV/master" 2>/dev/null)" 2>/dev/null || true
        fi

        printf '\n'

    done

    if command_exists bridge; then

        printf '\nDSA / VLAN table:\n'
        run_cmd "bridge vlan show"

    else

        printf '\nКоманда bridge отсутствует.\n'

    fi


    # ========================================================
    # 17. UCI NETWORK
    # ========================================================

    section "17. UCI NETWORK"

    run_cmd "uci show network"


    # ========================================================
    # 18. UCI DHCP
    # ========================================================

    section "18. UCI DHCP"

    run_cmd "uci show dhcp"


    # ========================================================
    # 19. UCI FIREWALL
    # ========================================================

    section "19. UCI FIREWALL"

    run_cmd "uci show firewall"


    # ========================================================
    # 20. SYSTEM BOARD
    # ========================================================

    section "20. SYSTEM BOARD"

    if command_exists ubus; then
        run_cmd "ubus call system board"
    else
        printf 'ubus отсутствует.\n'
    fi


    # ========================================================
    # 21. WAN INTERFACE STATUS
    # ========================================================

    section "21. WAN STATUS"

    if command_exists ubus; then

        run_cmd "ubus call network.interface.wan status"

    else

        printf 'ubus отсутствует.\n'

    fi


    # ========================================================
    # 22. IFSTATUS WAN
    # ========================================================

    section "22. IFSTATUS WAN"

    if command_exists ifstatus; then

        run_cmd "ifstatus wan"

    else

        printf 'Команда ifstatus отсутствует.\n'

    fi


    # ========================================================
    # 23. WAN UCI CONFIGURATION
    # ========================================================

    section "23. WAN UCI CONFIGURATION"

    printf '\nWAN protocol:\n'
    uci_get "network.wan.proto"

    printf '\nWAN device:\n'
    uci_get "network.wan.device"

    printf '\nWAN network:\n'
    uci_get "network.wan.network"

    printf '\nWAN type:\n'
    uci_get "network.wan.type"

    printf '\nWAN IPv6:\n'
    uci_get "network.wan.ipv6"

    printf '\nWAN metric:\n'
    uci_get "network.wan.metric"


    # ========================================================
    # 24. WAN DEVICE DETAILS
    # ========================================================

    section "24. WAN DEVICE DETAILS"

    WAN_DEVICE="$(uci_get "network.wan.device")"

    if [ -z "$WAN_DEVICE" ]; then

        printf 'network.wan.device не задан.\n'

        printf '\nПопытка получить L3 device через ifstatus:\n'

        if command_exists ifstatus; then

            ifstatus wan 2>/dev/null \
                | grep -E '"l3_device"|"device"|"ipv4-address"|"route"' || true

        fi

    else

        printf 'WAN device из UCI: %s\n' "$WAN_DEVICE"

        if ip link show dev "$WAN_DEVICE" >/dev/null 2>&1; then

            run_cmd "ip addr show dev $WAN_DEVICE"

            printf '\nLink state:\n'
            cat "/sys/class/net/$WAN_DEVICE/operstate" 2>/dev/null || true

            printf '\nMTU:\n'
            cat "/sys/class/net/$WAN_DEVICE/mtu" 2>/dev/null || true

            printf '\nMAC:\n'
            cat "/sys/class/net/$WAN_DEVICE/address" 2>/dev/null || true

        else

            printf 'Интерфейс %s отсутствует в ip link.\n' "$WAN_DEVICE"

        fi

    fi


    # ========================================================
    # 25. LAN INTERFACE DETAILS
    # ========================================================

    section "25. LAN INTERFACE DETAILS"

    LAN_DEVICE="$(uci_get "network.lan.device")"

    printf 'LAN device: %s\n' "$LAN_DEVICE"

    if [ -n "$LAN_DEVICE" ]; then

        if ip link show dev "$LAN_DEVICE" >/dev/null 2>&1; then

            run_cmd "ip addr show dev $LAN_DEVICE"

            printf '\nOperational state:\n'
            cat "/sys/class/net/$LAN_DEVICE/operstate" 2>/dev/null || true

            printf '\nMTU:\n'
            cat "/sys/class/net/$LAN_DEVICE/mtu" 2>/dev/null || true

            printf '\nMAC:\n'
            cat "/sys/class/net/$LAN_DEVICE/address" 2>/dev/null || true

            printf '\nBridge ports:\n'
            ls -1 "/sys/class/net/$LAN_DEVICE/brif" 2>/dev/null || true

        else

            printf 'Интерфейс %s отсутствует.\n' "$LAN_DEVICE"

        fi

    fi


    # ========================================================
    # 26. DHCP CONFIGURATION SUMMARY
    # ========================================================

    section "26. DHCP SUMMARY"

    printf '\nLAN DHCP interface:\n'
    uci_get "dhcp.lan.interface"

    printf '\nDHCP start:\n'
    uci_get "dhcp.lan.start"

    printf '\nDHCP limit:\n'
    uci_get "dhcp.lan.limit"

    printf '\nDHCP lease time:\n'
    uci_get "dhcp.lan.leasetime"

    printf '\nDHCP ignore:\n'
    uci_get "dhcp.lan.ignore"


    # ========================================================
    # 27. DHCP SERVICE
    # ========================================================

    section "27. DHCP SERVICE"

    if pidof dnsmasq >/dev/null 2>&1; then

        printf 'dnsmasq: RUNNING\n'

        printf 'PID:\n'
        pidof dnsmasq

    else

        printf 'dnsmasq: NOT RUNNING\n'

    fi


    # ========================================================
    # 28. DNS
    # ========================================================

    section "28. DNS"

    if [ -f /etc/resolv.conf ]; then

        run_cmd "cat /etc/resolv.conf"

    else

        printf '/etc/resolv.conf отсутствует.\n'

    fi


    # ========================================================
    # 29. DNSMASQ
    # ========================================================

    section "29. DNSMASQ"

    if pidof dnsmasq >/dev/null 2>&1; then

        printf 'dnsmasq: RUNNING\n'
        printf 'PID: '
        pidof dnsmasq

    else

        printf 'dnsmasq: NOT RUNNING\n'

    fi

    printf '\nDNSMasq process information:\n'

    if command_exists ps; then
        ps w 2>/dev/null | grep '[d]nsmasq' || true
    fi


    # ========================================================
    # 30. DNS RESOLVER POLICY
    # ========================================================

    section "30. DNS RESOLVER POLICY / DoT"

    printf '\nnoresolv:\n'

    DNS_NORESOLV="$(uci_get "dhcp.@dnsmasq[0].noresolv")"

    if [ -n "$DNS_NORESOLV" ]; then
        printf '%s\n' "$DNS_NORESOLV"
    else
        printf 'не задано\n'
    fi

    printf '\nserver settings:\n'

    uci -q show dhcp 2>/dev/null \
        | grep -E '^dhcp\.@dnsmasq\[0\]\.server=' || true

    printf '\nRaw dnsmasq resolver configuration:\n'

    uci -q show dhcp 2>/dev/null \
        | grep -E '(^dhcp\.@dnsmasq\[0\]\.(noresolv|server|resolvfile|localservice|rebind_protection|rebind_localhost|domainneeded|boguspriv)=)' \
        || true

    printf '\n/etc/resolv.conf:\n'

    if [ -f /etc/resolv.conf ]; then
        cat /etc/resolv.conf
    fi

    printf '\nDNS listening sockets:\n'

    if command_exists ss; then
        ss -lntup 2>/dev/null \
            | grep -E '(:53[[:space:]]|dnsmasq)' || true
    fi


    # ========================================================
    # 31. FIREWALL SERVICE
    # ========================================================

    section "31. FIREWALL SERVICE"

    if [ -x /etc/init.d/firewall ]; then

        /etc/init.d/firewall status 2>&1 || true

    else

        printf '/etc/init.d/firewall отсутствует.\n'

    fi


    # ========================================================
    # 32. FIREWALL ZONES
    # ========================================================

    section "32. FIREWALL ZONES"

    printf '\nFirewall zones:\n'

    uci -q show firewall 2>/dev/null \
        | grep -E '^firewall\.@zone\[[0-9]+\]\.' || true


    # ========================================================
    # 33. FIREWALL FORWARDINGS
    # ========================================================

    section "33. FIREWALL FORWARDINGS"

    printf '\nFirewall forwardings:\n'

    uci -q show firewall 2>/dev/null \
        | grep -E '^firewall\.@forwarding\[[0-9]+\]\.' || true


    # ========================================================
    # 34. FIREWALL RULES
    # ========================================================

    section "34. FIREWALL RULES"

    uci -q show firewall 2>/dev/null \
        | grep -E '^firewall\.@rule\[[0-9]+\]\.' || true


    # ========================================================
    # 35. NFTABLES
    # ========================================================

    section "35. FIREWALL / NFTABLES"

    if command_exists nft; then

        printf '\nNFTables ruleset:\n'
        run_cmd "nft list ruleset"

        printf '\nNFTables tables:\n'
        run_cmd "nft list tables"

    else

        printf 'nft отсутствует.\n'

    fi


    # ========================================================
    # 36. NFTABLES COUNTERS
    # ========================================================

    section "36. NFTABLES COUNTERS / TRAFFIC STATISTICS"

    if command_exists nft; then

        printf '\nВсе counters:\n'
        run_cmd "nft list counters"

        printf '\nCounters внутри полного ruleset:\n'
        run_cmd "nft -a list ruleset | grep -E 'counter|packets|bytes'"

    else

        printf 'nft отсутствует.\n'

    fi


    # ========================================================
    # 37. NAT
    # ========================================================

    section "37. NAT"

    if command_exists nft; then

        printf '\nNFTables NAT tables/chains/rules:\n'

        run_cmd "nft list table ip nat"

        printf '\nIPv4 NAT-related rules from complete ruleset:\n'

        nft -a list ruleset 2>/dev/null \
            | grep -Ei 'nat|masquerade|snat|dnat|redirect' || true

    else

        printf 'nft отсутствует.\n'

    fi


    # ========================================================
    # 38. CONNECTION TRACKING
    # ========================================================

    section "38. CONNECTION TRACKING"

    if [ -f /proc/sys/net/netfilter/nf_conntrack_count ]; then

        printf 'Current conntrack entries:\n'
        cat /proc/sys/net/netfilter/nf_conntrack_count

    else

        printf 'nf_conntrack_count отсутствует.\n'

    fi

    if [ -f /proc/sys/net/netfilter/nf_conntrack_max ]; then

        printf '\nMaximum conntrack entries:\n'
        cat /proc/sys/net/netfilter/nf_conntrack_max

    else

        printf '\nnf_conntrack_max отсутствует.\n'

    fi

    if command_exists conntrack; then

        printf '\nConntrack summary:\n'
        run_cmd "conntrack -S"

    else

        printf '\nКоманда conntrack отсутствует.\n'

    fi


    # ========================================================
    # 39. DHCP LEASES
    # ========================================================

    section "39. DHCP LEASES"

    if [ -f /tmp/dhcp.leases ]; then

        run_cmd "cat /tmp/dhcp.leases"

    else

        printf '/tmp/dhcp.leases отсутствует.\n'

    fi


    # ========================================================
    # 40. NEIGHBOURS
    # ========================================================

    section "40. ARP / NEIGHBOURS"

    run_cmd "ip neigh"


    # ========================================================
    # 41. SOCKETS
    # ========================================================

    section "41. ПРОСЛУШИВАЕМЫЕ ПОРТЫ"

    if command_exists ss; then

        run_cmd "ss -lntup"

    elif command_exists netstat; then

        run_cmd "netstat -lntup"

    else

        printf 'ss и netstat отсутствуют.\n'

    fi


    # ========================================================
    # 42. ROUTER SERVICES
    # ========================================================

    section "42. ОСНОВНЫЕ СЕТЕВЫЕ СЕРВИСЫ"

    printf '\nProcesses:\n'

    if command_exists ps; then

        ps w 2>/dev/null \
            | grep -E '[d]nsmasq|[u]httpd|[u]httpd-ssl|[n]ginx|[d]ropbear|[o]penvpn|[w]ireguard|[u]nbound|[s]martdns' \
            || true

    fi


    # ========================================================
    # 43. NETWORK DEVICE STATISTICS
    # ========================================================

    section "43. NETWORK DEVICE STATISTICS"

    run_cmd "ip -s link"


    # ========================================================
    # 44. ETHTOOL INFORMATION
    # ========================================================

    section "44. LINK / ETHERNET INFORMATION"

    if command_exists ethtool; then

        for DEV in /sys/class/net/*; do

            [ -e "$DEV" ] || continue

            NAME="$(basename "$DEV")"

            case "$NAME" in
                lo|br-*|docker*|virbr*|veth*)
                    continue
                    ;;
            esac

            printf '\n--- %s ---\n' "$NAME"

            ethtool "$NAME" 2>/dev/null \
                | grep -E 'Speed:|Duplex:|Auto-negotiation:|Link detected:' \
                || true

        done

    else

        printf 'ethtool отсутствует.\n'

    fi


    # ========================================================
    # 45. MAIN CONFIG FILES
    # ========================================================

    section "45. ОСНОВНЫЕ CONFIG FILES"

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
    # 46. DHCP / DNS CONFIGURATION FILES
    # ========================================================

    section "46. DHCP / DNS CONFIGURATION FILES"

    printf '\n/etc/resolv.conf:\n'

    if [ -f /etc/resolv.conf ]; then
        cat /etc/resolv.conf
    else
        printf '/etc/resolv.conf отсутствует.\n'
    fi

    printf '\n/etc/config/system:\n'

    if [ -f /etc/config/system ]; then
        cat /etc/config/system
    else
        printf '/etc/config/system отсутствует.\n'
    fi


    # ========================================================
    # 47. UCI DNS SUMMARY
    # ========================================================

    section "47. DNS CONFIGURATION SUMMARY"

    printf '\nDnsmasq noresolv:\n'
    uci_get "dhcp.@dnsmasq[0].noresolv"

    printf '\nDnsmasq server:\n'
    uci_get "dhcp.@dnsmasq[0].server"

    printf '\nDnsmasq resolvfile:\n'
    uci_get "dhcp.@dnsmasq[0].resolvfile"

    printf '\nDNS forwardings from UCI:\n'

    uci -q show dhcp 2>/dev/null \
        | grep -E 'server=' || true


    # ========================================================
    # 48. FIREWALL DEFAULT POLICY SUMMARY
    # ========================================================

    section "48. FIREWALL DEFAULT POLICY SUMMARY"

    printf '\nDefault input policies:\n'

    uci -q show firewall 2>/dev/null \
        | grep -E '\.input=' || true

    printf '\nDefault output policies:\n'

    uci -q show firewall 2>/dev/null \
        | grep -E '\.output=' || true

    printf '\nDefault forward policies:\n'

    uci -q show firewall 2>/dev/null \
        | grep -E '\.forward=' || true

    printf '\nMasquerading settings:\n'

    uci -q show firewall 2>/dev/null \
        | grep -E '\.masq=' || true


    # ========================================================
    # 49. CURRENT NETWORK STATE
    # ========================================================

    section "49. CURRENT NETWORK STATE"

    if command_exists ubus; then

        printf '\nNetwork dump:\n'
        run_cmd "ubus call network.interface dump"

    else

        printf 'ubus отсутствует.\n'

    fi


    # ========================================================
    # 50. FINAL SUMMARY
    # ========================================================

    section "50. ИТОГОВАЯ СВОДКА"

    printf '\nHostname:\n'
    printf '%s\n' "$HOST"


    printf '\nModel:\n'

    if command_exists ubus; then

        ubus call system board 2>/dev/null \
            | grep '"model"' || true

    fi


    printf '\nOpenWrt:\n'

    if command_exists ubus; then

        ubus call system board 2>/dev/null \
            | grep '"description"' || true

    fi


    printf '\nWAN protocol:\n'
    uci_get "network.wan.proto"


    printf '\nWAN configured device:\n'
    uci_get "network.wan.device"


    printf '\nWAN IPv4:\n'

    if command_exists ifstatus; then

        ifstatus wan 2>/dev/null \
            | grep -A8 '"ipv4-address"' || true

    else

        printf 'ifstatus отсутствует.\n'

    fi


    printf '\nDefault route:\n'
    ip route 2>/dev/null | grep '^default' || true


    printf '\nLAN address:\n'
    uci_get "network.lan.ipaddr"


    printf '\nLAN netmask:\n'
    uci_get "network.lan.netmask"


    printf '\nLAN device:\n'
    uci_get "network.lan.device"


    printf '\nLAN bridge ports:\n'

    LAN_DEVICE="$(uci_get "network.lan.device")"

    if [ -n "$LAN_DEVICE" ] && [ -d "/sys/class/net/$LAN_DEVICE/brif" ]; then

        ls -1 "/sys/class/net/$LAN_DEVICE/brif" 2>/dev/null || true

    elif [ -d /sys/class/net/br-lan/brif ]; then

        ls -1 /sys/class/net/br-lan/brif 2>/dev/null || true

    else

        printf 'Bridge ports не обнаружены.\n'

    fi


    printf '\nIPv4 forwarding:\n'

    if [ -f /proc/sys/net/ipv4/ip_forward ]; then
        cat /proc/sys/net/ipv4/ip_forward
    else
        printf 'unknown\n'
    fi


    printf '\nDHCP interface:\n'
    uci_get "dhcp.lan.interface"


    printf '\nDHCP range start:\n'
    uci_get "dhcp.lan.start"


    printf '\nDHCP range limit:\n'
    uci_get "dhcp.lan.limit"


    printf '\nDHCP lease time:\n'
    uci_get "dhcp.lan.leasetime"


    printf '\nDNS noresolv:\n'
    uci_get "dhcp.@dnsmasq[0].noresolv"


    printf '\nDNS upstream servers:\n'
    uci_get "dhcp.@dnsmasq[0].server"


    printf '\nFirewall service:\n'

    if [ -x /etc/init.d/firewall ]; then

        /etc/init.d/firewall status 2>&1 || true

    else

        printf 'unknown\n'

    fi


    printf '\nNFTables:\n'

    if command_exists nft; then

        printf 'installed\n'

    else

        printf 'not installed\n'

    fi


    printf '\nConntrack:\n'

    if [ -f /proc/sys/net/netfilter/nf_conntrack_count ]; then

        cat /proc/sys/net/netfilter/nf_conntrack_count

    else

        printf 'unknown\n'

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
