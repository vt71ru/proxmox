#!/usr/bin/env bash

# ============================================================
# Proxmox Lab
#
# VM 101  = OPNsense
# LXC 102 = Debian Web
# LXC 103 = Debian Database
# LXC 104 = Debian Git
#
# WAN:
#   vmbr0
#   192.168.1.221/24 (Proxmox)
#
# LAN:
#   vmbr1
#   10.10.10.254/24 (Proxmox)
#
# OPNsense:
#   WAN -> vmbr0
#   LAN -> vmbr1
#   LAN IP -> 10.10.10.1/24
#
# Debian:
#   Web      10.10.10.20/24
#   Database 10.10.10.30/24
#   Git      10.10.10.40/24
#
# ВАЖНО:
# Скрипт создаёт системы, но НЕ запускает их.
# Сначала настраиваем OPNsense.
# ============================================================

set -Eeuo pipefail

LOG_FILE="/var/log/deploy-lab.log"

exec > >(tee -a "$LOG_FILE") 2>&1

# ============================================================
# Configuration
# ============================================================

STORAGE="local"

WAN_BRIDGE="vmbr0"
LAN_BRIDGE="vmbr1"

PROXMOX_WAN_IP="192.168.1.221/24"
PROXMOX_WAN_GW="192.168.1.1"

PROXMOX_LAN_IP="10.10.10.254/24"

LAN_NETWORK="10.10.10.0/24"
LAN_GATEWAY="10.10.10.1"

DNS_SERVER="10.10.10.1"

SSH_PUBLIC_KEY="/root/.ssh/id_ed25519.pub"

OPNSENSE_IMAGE="/var/lib/vz/template/qemu/opnsense.qcow2"

# VM IDs

OPNSENSE_ID=101
WEB_ID=102
DB_ID=103
GIT_ID=104

# Resources

OPNSENSE_NAME="Router-Firewall-DNS"
OPNSENSE_RAM=3072
OPNSENSE_CORES=2
OPNSENSE_DISK="16G"

WEB_NAME="Web"
WEB_RAM=2048
WEB_CORES=2
WEB_DISK="20G"
WEB_IP="10.10.10.20/24"

DB_NAME="Database"
DB_RAM=2048
DB_CORES=2
DB_DISK="20G"
DB_IP="10.10.10.30/24"

GIT_NAME="Git"
GIT_RAM=2048
GIT_CORES=2
GIT_DISK="20G"
GIT_IP="10.10.10.40/24"

# LXC configuration

LXC_UNPRIVILEGED=1
LXC_SWAP=512

# ============================================================
# Functions
# ============================================================

log() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

die() {
    echo
    echo "ERROR:"
    echo "$1"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 \
        || die "Не найдена команда: $1"
}

vm_exists() {
    qm status "$1" >/dev/null 2>&1
}

ct_exists() {
    pct status "$1" >/dev/null 2>&1
}

# ============================================================
# Initial checks
# ============================================================

check_root() {

    [[ "$(id -u)" -eq 0 ]] \
        || die "Скрипт нужно запускать от root."

}

check_commands() {

    local commands=(
        qm
        pct
        pveam
        pvesm
        ip
        curl
        qemu-img
        ifreload
        awk
        sed
        grep
        sort
        tee
    )

    for command in "${commands[@]}"; do
        require_command "$command"
    done

}

check_storage() {

    log "Проверка storage"

    pvesm status --storage "$STORAGE" >/dev/null 2>&1 \
        || die "Storage '$STORAGE' не найден."

    echo "Storage:"
    pvesm status --storage "$STORAGE"

}

check_vm_ids() {

    log "Проверка VM/CT ID"

    local ids=(
        "$OPNSENSE_ID"
        "$WEB_ID"
        "$DB_ID"
        "$GIT_ID"
    )

    for id in "${ids[@]}"; do

        if vm_exists "$id"; then
            die "VM ID $id уже существует."
        fi

        if ct_exists "$id"; then
            die "LXC ID $id уже существует."
        fi

    done

}

check_ssh_key() {

    log "Проверка SSH public key"

    [[ -f "$SSH_PUBLIC_KEY" ]] \
        || die "Не найден $SSH_PUBLIC_KEY"

    echo "SSH public key:"
    cat "$SSH_PUBLIC_KEY"

}

check_wan() {

    log "Проверка существующего vmbr0"

    ip link show "$WAN_BRIDGE" >/dev/null 2>&1 \
        || die "$WAN_BRIDGE не существует."

    echo
    echo "vmbr0:"
    ip -br addr show "$WAN_BRIDGE"

    echo
    echo "Routing:"
    ip route

}

check_opnsense_image() {

    log "Проверка OPNsense image"

    [[ -f "$OPNSENSE_IMAGE" ]] \
        || die "Не найден OPNsense image:

$OPNSENSE_IMAGE"

    qemu-img info "$OPNSENSE_IMAGE"

}

# ============================================================
# Old route
# ============================================================

remove_old_route() {

    log "Проверка старого маршрута 10.10.10.0/24"

    if grep -Eq \
        '10\.10\.10\.0/24 via 192\.168\.1\.164 dev vmbr0' \
        /etc/network/interfaces; then

        echo "Обнаружен старый persistent route."

        sed -i \
            '/10\.10\.10\.0\/24 via 192\.168\.1\.164 dev vmbr0/d' \
            /etc/network/interfaces

        echo "Удалён из /etc/network/interfaces."

    else

        echo "Persistent route не найден."

    fi

    if ip route show \
        | grep -q '10\.10\.10\.0/24 via 192\.168\.1\.164'; then

        echo "Удаляю runtime route..."

        ip route del \
            10.10.10.0/24 \
            via 192.168.1.164 \
            dev "$WAN_BRIDGE" \
            || true

    else

        echo "Runtime route не найден."

    fi

}

# ============================================================
# Internal bridge
# ============================================================

create_internal_bridge() {

    log "Создание vmbr1"

    if grep -q "^auto ${LAN_BRIDGE}$" \
        /etc/network/interfaces; then

        echo "vmbr1 уже существует."

        grep -A10 \
            "^iface ${LAN_BRIDGE}" \
            /etc/network/interfaces \
            || true

        return

    fi

    cat >> /etc/network/interfaces <<EOF

# ============================================================
# Internal Lab Network
# ============================================================

auto ${LAN_BRIDGE}
iface ${LAN_BRIDGE} inet static
        address ${PROXMOX_LAN_IP}
        bridge-ports none
        bridge-stp off
        bridge-fd 0

EOF

    echo "vmbr1 добавлен."

}

apply_network() {

    log "Применение сетевой конфигурации"

    ifreload -a

    sleep 3

    echo
    echo "vmbr0:"
    ip -br addr show "$WAN_BRIDGE"

    echo
    echo "vmbr1:"
    ip -br addr show "$LAN_BRIDGE"

}

# ============================================================
# Debian LXC template
# ============================================================

find_debian_template() {

    log "Поиск Debian 13 LXC template"

    local template

    template="$(
        pveam available --section system \
        | awk '$1=="system" &&
               $2 ~ /^debian-13-standard_/ &&
               $2 ~ /_amd64\.tar\.(zst|xz|gz)$/ {print $2}' \
        | sort -V \
        | tail -n1
    )"

    [[ -n "$template" ]] \
        || die "Debian 13 standard LXC template не найден."

    echo "$template"

    DEBIAN_TEMPLATE="$template"

}

download_debian_template() {

    log "Загрузка Debian LXC template"

    if pveam list "$STORAGE" \
        | grep -q "$DEBIAN_TEMPLATE"; then

        echo "Template уже существует:"
        echo "$DEBIAN_TEMPLATE"
        return

    fi

    pveam download \
        "$STORAGE" \
        "$DEBIAN_TEMPLATE"

}

get_template_path() {

    local template_path

    template_path="$(
        pveam list "$STORAGE" \
        | awk -v name="$DEBIAN_TEMPLATE" '$2==name {print $1; exit}'
    )"

    [[ -n "$template_path" ]] \
        || die "Не удалось найти скачанный template."

    echo "$template_path"

    DEBIAN_TEMPLATE_PATH="$template_path"

}

# ============================================================
# OPNsense VM
# ============================================================

create_opnsense() {

    log "Создание OPNsense VM 101"

    qm create "$OPNSENSE_ID" \
        --name "$OPNSENSE_NAME" \
        --memory "$OPNSENSE_RAM" \
        --cores "$OPNSENSE_CORES" \
        --ostype other \
        --machine q35 \
        --bios seabios \
        --net0 "virtio,bridge=${WAN_BRIDGE}" \
        --net1 "virtio,bridge=${LAN_BRIDGE}" \
        --vga std \
        --onboot 1 \
        --startup "order=10,up=30"

    echo
    echo "Импорт диска OPNsense..."

    qm importdisk \
        "$OPNSENSE_ID" \
        "$OPNSENSE_IMAGE" \
        "$STORAGE"

    local imported_disk

    imported_disk="$(
        qm config "$OPNSENSE_ID" \
        | awk -F': ' '/^unused[0-9]+:/ {print $2; exit}'
    )"

    [[ -n "$imported_disk" ]] \
        || die "Не найден imported OPNsense disk."

    echo "Imported disk:"
    echo "$imported_disk"

    qm set "$OPNSENSE_ID" \
        --sata0 "$imported_disk"

    qm set "$OPNSENSE_ID" \
        --boot order=sata0

    echo
    echo "OPNsense VM:"
    qm config "$OPNSENSE_ID"

}

# ============================================================
# LXC helper
# ============================================================

create_lxc() {

    local id="$1"
    local hostname="$2"
    local memory="$3"
    local cores="$4"
    local disk="$5"
    local ip="$6"

    log "Создание LXC $id ($hostname)"

    pct create "$id" \
        "$DEBIAN_TEMPLATE_PATH" \
        --hostname "$hostname" \
        --arch amd64 \
        --cores "$cores" \
        --memory "$memory" \
        --swap "$LXC_SWAP" \
        --rootfs "${STORAGE}:${disk}" \
        --net0 "name=eth0,bridge=${LAN_BRIDGE},ip=${ip},gw=${LAN_GATEWAY}" \
        --nameserver "$DNS_SERVER" \
        --searchdomain "lab.local" \
        --unprivileged "$LXC_UNPRIVILEGED" \
        --onboot 1 \
        --startup "order=20,up=30" \
        --features "nesting=1"

    echo
    echo "LXC configuration:"
    pct config "$id"

}

# ============================================================
# LXC creation
# ============================================================

create_containers() {

    create_lxc \
        "$WEB_ID" \
        "$WEB_NAME" \
        "$WEB_RAM" \
        "$WEB_CORES" \
        "$WEB_DISK" \
        "$WEB_IP"

    create_lxc \
        "$DB_ID" \
        "$DB_NAME" \
        "$DB_RAM" \
        "$DB_CORES" \
        "$DB_DISK" \
        "$DB_IP"

    create_lxc \
        "$GIT_ID" \
        "$GIT_NAME" \
        "$GIT_RAM" \
        "$GIT_CORES" \
        "$GIT_DISK" \
        "$GIT_IP"

}

# ============================================================
# Result
# ============================================================

show_result() {

    log "РАЗВЁРТЫВАНИЕ ЗАВЕРШЕНО"

    cat <<EOF

============================================================
NETWORK
============================================================

WAN:
    ${WAN_BRIDGE}
    192.168.1.221/24
    gateway 192.168.1.1

LAN:
    ${LAN_BRIDGE}
    10.10.10.254/24
    bridge-ports none

OPNsense LAN:
    10.10.10.1/24

============================================================
OPNsense VM
============================================================

VM ID:
    ${OPNSENSE_ID}

Name:
    ${OPNSENSE_NAME}

WAN:
    ${WAN_BRIDGE}

LAN:
    ${LAN_BRIDGE}

============================================================
LXC 102
============================================================

Name:
    ${WEB_NAME}

IP:
    10.10.10.20/24

Gateway:
    10.10.10.1

DNS:
    10.10.10.1

============================================================
LXC 103
============================================================

Name:
    ${DB_NAME}

IP:
    10.10.10.30/24

Gateway:
    10.10.10.1

DNS:
    10.10.10.1

============================================================
LXC 104
============================================================

Name:
    ${GIT_NAME}

IP:
    10.10.10.40/24

Gateway:
    10.10.10.1

DNS:
    10.10.10.1

============================================================
CURRENT STATUS
============================================================

Все системы СОЗДАНЫ, но НЕ ЗАПУЩЕНЫ.

Следующий шаг:

    qm start 101

После настройки OPNsense:

    pct start 102
    pct start 103
    pct start 104

============================================================
CONFIG FILE
============================================================

    /etc/network/interfaces

LOG:

    ${LOG_FILE}

============================================================
EOF

}

# ============================================================
# Main
# ============================================================

main() {

    log "PROXMOX OPNsense + Debian LXC LAB"

    check_root
    check_commands
    check_storage
    check_vm_ids
    check_ssh_key
    check_wan
    check_opnsense_image

    remove_old_route

    create_internal_bridge
    apply_network

    find_debian_template
    download_debian_template
    get_template_path

    create_opnsense
    create_containers

    show_result
}

main "$@"
