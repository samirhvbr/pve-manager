#!/bin/bash
# Blue3 Cloud: serve the PVE web UI on TCP 80 and 443, not only on 8006.
#
#   ssh root@<node> bash -s < blue3-deploy/web-redirect/web-redirect.sh
#   ssh root@<node> bash -s -- status    < blue3-deploy/web-redirect/web-redirect.sh
#   ssh root@<node> bash -s -- uninstall < blue3-deploy/web-redirect/web-redirect.sh
#
# Runs from a workstation, and nothing has to be copied to the node first.
# It is idempotent and touches nothing but its own nft table and its own
# systemd unit.
#
# Why a port redirect and not a reverse proxy: the redirect rewrites only the
# destination port, so pveproxy still sees the client's real source IP. Behind
# nginx, every request would come from 127.0.0.1. That address is in the
# ALLOW_FROM line that blue3-deploy/preflight.sh builds, so the lockdown would
# let everyone through, and fail2ban would only ever see 127.0.0.1.
#
# Plain HTTP on 80 works too. pveproxy answers a non-TLS request on 8006 with a
# 301 to https://<Host header>/, and that lands on 443.

set -euo pipefail

NFT_FILE=/etc/blue3/web-redirect.nft
UNIT=blue3-web-redirect.service
UNIT_FILE=/etc/systemd/system/$UNIT
TABLE="inet blue3_web"

ok()  { printf '  \e[32m✓\e[0m %s\n' "$1"; }
die() { printf '  \e[31m✗\e[0m %s\n' "$1"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root"

install_redirect() {
    command -v nft >/dev/null || die "nft not found (package nftables)"

    # Something already listening on 80/443 would be shadowed silently.
    if ss -ltnH '( sport = :80 or sport = :443 )' | grep -q .; then
        ss -ltnp '( sport = :80 or sport = :443 )'
        die "something already listens on 80/443, refusing to shadow it"
    fi

    install -d -m 755 /etc/blue3
    cat > "$NFT_FILE" <<'EOF'
#!/usr/sbin/nft -f
# Managed by blue3-deploy/web-redirect/web-redirect.sh. Edits are overwritten.
#
# Only connections addressed to one of this node's own addresses are
# redirected. Without the fib match, bridged guest traffic would have its
# outbound HTTP/HTTPS hijacked to pveproxy. These hooks see that traffic once
# br_netfilter is loaded, for example when the PVE firewall is on.
#
# Firewall rules, whether the PVE firewall or the runbook's step 6, only need
# to allow 8006. The filter hooks run after this and see the translated port.

table inet blue3_web
delete table inet blue3_web

table inet blue3_web {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        fib daddr type local tcp dport { 80, 443 } redirect to :8006
    }
}
EOF
    nft -c -f "$NFT_FILE" || die "ruleset does not parse"

    cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Blue3 Cloud: redirect TCP 80/443 to the PVE web UI on 8006
Documentation=https://github.com/samirhvbr/pve-manager/blob/master/docs/new-node.md
Before=pveproxy.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nft -f $NFT_FILE
ExecReload=/usr/sbin/nft -f $NFT_FILE
ExecStop=-/usr/sbin/nft delete table $TABLE

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --quiet "$UNIT"
    systemctl restart "$UNIT"
    nft list table $TABLE >/dev/null 2>&1 || die "table $TABLE is not loaded"
    ok "$UNIT enabled, table $TABLE loaded"

    local ip
    ip=$(hostname -i | awk '{print $1}')
    printf '\n  Check from another machine (redirects do not apply to local traffic):\n'
    # GET, not curl -I: pveproxy answers HEAD with 501
    printf "    curl -s -o /dev/null -w '%%{http_code} %%{redirect_url}\\\\n' http://%s/   # -> 301 https://%s/\n" "$ip" "$ip"
    printf "    curl -skL http://%s/ | grep -o '<title>[^<]*'                        # -> <node> - Blue3 Cloud\n" "$ip"
}

uninstall_redirect() {
    systemctl disable --now --quiet "$UNIT" 2>/dev/null || true
    rm -f "$UNIT_FILE" "$NFT_FILE"
    rmdir /etc/blue3 2>/dev/null || true
    systemctl daemon-reload
    nft delete table $TABLE 2>/dev/null || true
    ok "removed; the UI answers on 8006 only"
}

status_redirect() {
    printf '  unit:  %s (%s)\n' "$(systemctl is-active "$UNIT" 2>/dev/null || true)" \
        "$(systemctl is-enabled "$UNIT" 2>/dev/null || true)"
    nft list table $TABLE 2>/dev/null | sed 's/^/  /' || echo "  table $TABLE: not loaded"
}

case "${1:-install}" in
    install)   install_redirect ;;
    uninstall) uninstall_redirect ;;
    status)    status_redirect ;;
    *)         die "usage: $0 [install|uninstall|status]" ;;
esac
