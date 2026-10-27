#!/bin/bash
# Blue3 Cloud: create vmbr1, the "Telefonia" bridge, on a cluster node.
#
#   ssh root@<node> bash -s           < blue3-deploy/network/vmbr1.sh   # port nic5
#   ssh root@<node> bash -s -- nic3   < blue3-deploy/network/vmbr1.sh   # another port
#   ssh root@<node> bash -s -- status < blue3-deploy/network/vmbr1.sh
#
# vmbr1 mirrors the bridge of the same name on the standalone host that the
# guests came from: a plain (not VLAN-aware) bridge on the second port of the
# 10G card, with no link. Guests in the same VLAN reach each other on the same
# node, and nothing leaves it. See docs/cluster.md, "Bridges".
#
# Why it needs a port at all: on a plain bridge, PVE builds one sub-bridge per
# VLAN tag on top of the bridge's physical port (vmbr1v<tag> on nic5.<tag>).
# With no port, it refuses to start a tagged NIC ("no physical interface on
# bridge").
#
# Only vmbr1 is touched. The stanza is appended to /etc/network/interfaces and
# brought up with `ifup vmbr1`, never `ifreload -a`, so vmbr0 (management and
# corosync) is never reloaded.

set -euo pipefail

IF=/etc/network/interfaces

ok()  { printf '  \e[32m✓\e[0m %s\n' "$1"; }
die() { printf '  \e[31m✗\e[0m %s\n' "$1"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root"
export LC_ALL=C

status() {
    if [ ! -e /sys/class/net/vmbr1 ]; then
        echo "vmbr1: absent"
        return
    fi
    echo "vmbr1: vlan_filtering=$(cat /sys/class/net/vmbr1/bridge/vlan_filtering)" \
         "ports=[$(ls /sys/class/net/vmbr1/brif | grep -vE '^(tap|fwpr|fwln|veth)' | tr '\n' ' ')]"
    grep -A6 '^iface vmbr1' "$IF" || echo "vmbr1 is not in $IF"
    [ -f "$IF.new" ] && echo "pending changes in $IF.new"
    return 0
}

carrier() { cat "/sys/class/net/$1/carrier" 2>/dev/null || echo 0; }

if [ "${1:-}" = status ]; then
    status
    exit 0
fi
PORT=${1:-nic5}

[ -d /etc/pve/nodes ] || die "not a PVE node"
[ -e /sys/class/net/vmbr1 ] && die "vmbr1 already exists"
grep -q '^iface vmbr1' "$IF" && die "vmbr1 is already defined in $IF"
# A pending GUI change would be applied over this file and drop vmbr1.
[ -f "$IF.new" ] && die "pending changes in $IF.new: Revert or Apply them in the UI first"
[ -e "/sys/class/net/$PORT" ] || die "no interface $PORT"
[ -e "/sys/class/net/$PORT/master" ] && die "$PORT already belongs to $(basename "$(readlink "/sys/class/net/$PORT/master")")"
grep -qE "^\s*bridge-ports\s.*\b$PORT\b" "$IF" && die "$PORT is a bridge port in $IF already"

# The port must have no link. Cabled to a trunk, every guest on vmbr1 would be
# on that wire, including router copies with one NIC per VLAN.
ip link set "$PORT" up
for _ in 1 2 3 4 5; do
    sleep 1
    if [ "$(carrier "$PORT")" = 1 ]; then
        ip link set "$PORT" down
        die "$PORT has link: it is cabled to something. Pick a port with no link."
    fi
done
ok "$PORT has no link"

backup="/root/interfaces.bak-$(date +%Y%m%d-%H%M%S)"
cp -a "$IF" "$backup"
ok "backup: $backup"
cat >> "$IF" <<EOF

auto vmbr1
iface vmbr1 inet manual
	bridge-ports $PORT
	bridge-stp off
	bridge-fd 0
#Telefonia
EOF

if ! ifup vmbr1; then
    cp -a "$backup" "$IF"
    ip link set "$PORT" down
    die "ifup vmbr1 failed: $IF restored from $backup"
fi

[ "$(cat /sys/class/net/vmbr1/bridge/vlan_filtering)" = 0 ] || die "vmbr1 came up VLAN-aware"
[ -e "/sys/class/net/vmbr1/brif/$PORT" ] || die "$PORT is not a port of vmbr1"
ok "vmbr1 is up on $PORT"
status
