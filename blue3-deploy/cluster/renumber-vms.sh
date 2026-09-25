#!/bin/bash
# Renumber QEMU VMs on the local node, e.g. to clear VMID conflicts before a
# host joins the cluster. VMIDs are cluster-unique, and the ID is part of every
# disk volume name, so a running VM has to be powered off to be renumbered.
#
#   bash renumber-vms.sh plan 102:202 101:201 100:200
#   bash renumber-vms.sh run  102:202 101:201 100:200
#
# `plan` changes nothing. Always run it first and read it.
# From a workstation:  ssh root@<node> bash -s -- plan 101:201 < renumber-vms.sh
#
# Scope: QEMU VMs whose disks are LVM or LVM-thin volumes, which covers vm-,
# base- and snap_ volumes, templates and snapshots. It does not handle
# containers, or directory, ZFS or Ceph storage. Linked clones of a renumbered
# template keep working, because LVM-thin tracks the origin internally, not by
# name.
#
# Not moved automatically: ACLs on /vms/<old>, firewall files
# (/etc/pve/firewall/<old>.fw), backup job VMID lists, HA and replication
# entries. Check them with: grep -rn '\b<old>\b' /etc/pve/*.cfg /etc/pve/firewall
#
# Used on b3p1 on 2026-09-25 (100/101/102 -> 200/201/202): 41 s total, and the
# running VMs were down for well under a minute each.

set -euo pipefail
export LC_ALL=C
MODE=${1:?usage: $0 plan|run old:new ...}; shift
[ "$MODE" = plan ] || [ "$MODE" = run ] || { echo "mode must be plan or run"; exit 1; }
[ $# -gt 0 ] || { echo "no old:new pairs given"; exit 1; }
CONF=/etc/pve/nodes/$(hostname)/qemu-server

run() { echo "  + $*"; if [ "$MODE" = run ]; then "$@"; fi; }

for pair in "$@"; do
    old=${pair%%:*}; new=${pair##*:}
    echo "== VM $old -> $new"
    [ -f "$CONF/$old.conf" ] || { echo "  $old.conf not on this node"; exit 1; }
    if grep -q "\"$new\"" /etc/pve/.vmlist; then echo "  VMID $new already used in the cluster"; exit 1; fi
    status=$(qm status "$old" | awk '{print $2}')
    echo "  status: $status"

    if [ "$status" = running ]; then
        # ACPI power button: works whether or not the guest agent is running
        run sh -c "echo system_powerdown | qm monitor $old >/dev/null"
        if [ "$MODE" = run ]; then
            qm wait "$old" --timeout 240 || { echo "  VM $old did not power off in 240 s; nothing renamed"; exit 1; }
            [ "$(qm status "$old" | awk '{print $2}')" = stopped ] || { echo "  VM $old still not stopped"; exit 1; }
            echo "  stopped"
        fi
    fi

    while read -r vg lv; do
        nlv=$(echo "$lv" | sed -E "s/^(vm|base)-$old-disk-/\1-$new-disk-/; s/^snap_(vm|base)-$old-disk-/snap_\1-$new-disk-/")
        [ "$nlv" != "$lv" ] || { echo "  cannot map LV $vg/$lv"; exit 1; }
        run lvrename "$vg" "$lv" "$nlv"
    done < <(lvs --noheadings -o vg_name,lv_name | awk -v o="$old" '$2 ~ "^(snap_)?(vm|base)-" o "-disk-" {print $1, $2}')

    if [ "$MODE" = run ]; then
        sed -E "s/\b(vm|base)-$old-disk-/\1-$new-disk-/g" "$CONF/$old.conf" > "$CONF/$new.conf"
        rm "$CONF/$old.conf"
        echo "  config moved to $new.conf"
        grep -oE "[A-Za-z0-9_.-]+:(vm|base)-$new-disk-[0-9]+" "$CONF/$new.conf" | sort -u | while read -r vol; do
            pvesm path "$vol" >/dev/null || { echo "  volume $vol does not resolve"; exit 1; }
        done
        echo "  volumes resolve"
        if [ "$status" = running ]; then
            qm start "$new"
            echo "  started: $(qm status "$new")"
        fi
    else
        echo "  + config $old.conf -> $new.conf, volume names $old -> $new"
        if [ "$status" = running ]; then echo "  + qm start $new"; fi
    fi
done
