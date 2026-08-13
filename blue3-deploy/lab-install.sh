#!/bin/bash
# Instala Proxmox VE 9 num Debian 13 (trixie) limpo — nó de laboratório.
#
#   bash lab-install.sh
#
# Idempotente: cada etapa checa antes de agir, então pode rodar de novo depois
# de corrigir alguma coisa.
#
# NÃO mexe em rede. A conversão de `ens18` para a bridge `vmbr0` é a única
# operação capaz de te deixar sem SSH, então ficou de fora de propósito — está
# documentada no fim, para ser feita com console disponível.

set -uo pipefail

RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; DIM=$'\e[2m'; RST=$'\e[0m'
ok()   { printf '  %s✓%s %s\n' "$GRN" "$RST" "$1"; }
warn() { printf '  %s!%s %s\n' "$YLW" "$RST" "$1"; }
die()  { printf '  %s✗%s %s\n' "$RED" "$RST" "$1"; exit 1; }
hdr()  { printf '\n%s── %s %s\n' "$DIM" "$1" "$RST"; }

[ "$(id -u)" -eq 0 ] || die "rode como root"

# ------------------------------------------------------------ pré-requisitos ---
hdr "Pré-requisitos"

. /etc/os-release
[ "${VERSION_CODENAME:-}" = "trixie" ] || die "esperado Debian trixie, achei '${VERSION_CODENAME:-?}'"
ok "Debian trixie"

# O pve-cluster resolve o próprio hostname para descobrir o IP de gerência.
# Apontando para 127.0.1.1 ele não sobe, e a formação de cluster falha depois.
HOSTIP=$(hostname -i 2>/dev/null | awk '{print $1}')
case "$HOSTIP" in
    127.*) die "hostname resolve para $HOSTIP — corrija /etc/hosts para o IP de gerência" ;;
    "")    die "hostname não resolve" ;;
    *)     ok "hostname resolve para $HOSTIP" ;;
esac

ROOTFREE=$(df --output=avail -BG / | tail -1 | tr -dc '0-9')
VARFREE=$(df --output=avail -BG /var | tail -1 | tr -dc '0-9')
[ "${ROOTFREE:-0}" -ge 10 ] || die "/ tem ${ROOTFREE}G livres, preciso de 10G+"
[ "${VARFREE:-0}" -ge 10 ]  || die "/var tem ${VARFREE}G livres, preciso de 10G+"
ok "espaço: / ${ROOTFREE}G · /var ${VARFREE}G"

# ------------------------------------------------------------------ egresso ---
hdr "Egresso"

for host in download.proxmox.com enterprise.proxmox.com; do
    if curl -sS --max-time 12 -o /dev/null "https://$host/" 2>/dev/null \
       || curl -sS --max-time 12 -o /dev/null "http://$host/" 2>/dev/null; then
        ok "$host alcançável"
    else
        die "$host INALCANÇÁVEL — libere TCP 80/443 de saída para esta VM antes de seguir"
    fi
done

# ----------------------------------------------------------------- repo PVE ---
hdr "Repositório Proxmox"

KEY=/usr/share/keyrings/proxmox-archive-keyring.gpg
if [ -s "$KEY" ]; then
    ok "chave já instalada"
else
    curl -fsSL -o "$KEY" https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg \
        || die "falhou baixar a chave"
    ok "chave baixada"
fi

# Confira a impressão digital contra o que a Proxmox publica antes de confiar.
printf '  %sfingerprint:%s\n' "$DIM" "$RST"
gpg --show-keys --with-fingerprint "$KEY" 2>/dev/null | sed -n '2p' | sed 's/^/    /'

LIST=/etc/apt/sources.list.d/pve.list
if grep -qs "download.proxmox.com/debian/pve" "$LIST" 2>/dev/null; then
    ok "repo já configurado"
else
    # pve-no-subscription: correto para laboratório. Em produção com assinatura,
    # troque por pve-enterprise.
    echo "deb [signed-by=$KEY] http://download.proxmox.com/debian/pve trixie pve-no-subscription" > "$LIST"
    ok "repo pve-no-subscription adicionado"
fi

apt-get update -qq || die "apt update falhou"
ok "apt update"

# ------------------------------------------------------------------- instala ---
hdr "Proxmox VE"

if dpkg -l proxmox-ve 2>/dev/null | grep -q '^ii'; then
    ok "proxmox-ve já instalado"
else
    warn "instalando proxmox-ve — puxa kernel novo, vai demorar"
    DEBIAN_FRONTEND=noninteractive apt-get install -y proxmox-ve postfix open-iscsi chrony \
        || die "instalação falhou"
    ok "proxmox-ve instalado"
fi

# O kernel do Debian não serve para PVE; o do Proxmox precisa estar ativo.
if uname -r | grep -q pve; then
    ok "rodando kernel PVE ($(uname -r))"
else
    warn "kernel atual é $(uname -r) — REINICIE para carregar o kernel PVE"
fi

# -------------------------------------------------------------------- resumo ---
hdr "Próximos passos"

cat <<'EOF'
  1. reboot  (para entrar no kernel PVE)

  2. Depois do boot, confirme:
       pveversion
       systemctl status pveproxy pvedaemon pvestatd

  3. A UI responde em https://<ip>:8006 com o pve-manager DE FÁBRICA.
     Nosso fork ainda não entrou — é o passo 4.

  4. Build do fork (as build-deps só existem com o repo PVE ativo):
       apt install -y proxmox-biome proxmox-widget-toolkit devscripts
       cd /root/pve-manager && make deb && dpkg -i ../pve-manager_*.deb

  5. bash blue3-deploy/preflight.sh

  REDE — faça só com console disponível:
  PVE quer uma bridge para os convidados. Hoje ens18 tem o IP direto. A
  conversão para vmbr0 pode te deixar sem SSH se sair errada:

      auto vmbr0
      iface vmbr0 inet static
          address 100.64.100.254/24
          gateway 100.64.100.1
          bridge-ports ens18
          bridge-stp off
          bridge-fd 0

  Para só testar o fork (UI, branding, pveproxy, WireGuard) a bridge NÃO é
  necessária — ela serve para dar rede a VMs criadas dentro do lab.
EOF
