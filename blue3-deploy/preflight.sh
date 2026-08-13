#!/bin/bash
# Preflight do runbook de blindagem — RODE NO NÓ, ANTES DE COMEÇAR.
#
# ESTE SCRIPT NÃO ALTERA NADA. Só lê estado e imprime o que você precisa saber.
# Pode rodar em produção, a qualquer hora, quantas vezes quiser.
#
#   bash preflight.sh
#
# O que ele resolve: o erro mais caro do runbook é o ALLOW_FROM do passo 7 sem
# todos os nós do cluster — o login funciona e a UI só quebra ao navegar para
# outro nó, um sintoma que não aponta para o arquivo certo. Aqui a linha sai
# pronta, montada a partir do cluster real.

set -uo pipefail

RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; DIM=$'\e[2m'; RST=$'\e[0m'
ok()   { printf '  %s✓%s %s\n' "$GRN" "$RST" "$1"; }
warn() { printf '  %s!%s %s\n' "$YLW" "$RST" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$RED" "$RST" "$1"; }
hdr()  { printf '\n%s── %s %s\n' "$DIM" "$1" "$RST"; }

WG_SUBNET="${WG_SUBNET:-10.99.0.0/24}"
FQDN="${FQDN:-pve.blue3.cloud}"

printf '\nPreflight — blindagem Blue3 Cloud\n'
printf '%sSomente leitura. Nada é alterado.%s\n' "$DIM" "$RST"

# ---------------------------------------------------------------- cluster ---
hdr "Cluster"

NODE_IPS=""

# corosync.conf é a fonte mais limpa: um ring0_addr por nó, sem depender de
# parsear saída de comando. Só existe se o cluster estiver formado.
if [ -r /etc/pve/corosync.conf ]; then
    NODE_IPS=$(grep -oE 'ring0_addr:[[:space:]]*[0-9.]+' /etc/pve/corosync.conf 2>/dev/null \
        | awk '{print $2}' | sort -u | tr '\n' ' ')
fi

# fallback: pvecm, que responde mesmo com a API fora do ar
if [ -z "${NODE_IPS// /}" ] && command -v pvecm >/dev/null 2>&1; then
    NODE_IPS=$(pvecm status 2>/dev/null \
        | awk '/^0x/ {for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print $i}' \
        | sort -u | tr '\n' ' ')
fi

COUNT=$(printf '%s' "$NODE_IPS" | wc -w)
if [ "$COUNT" -gt 1 ]; then
    ok "cluster com $COUNT nós: $NODE_IPS"
elif [ "$COUNT" -eq 1 ]; then
    warn "cluster com 1 nó só — se era para ter mais, pare e confira"
else
    warn "sem cluster detectado — tratando como nó único"
    # NÃO usar `hostname -I`: num host com Docker/bridges ele devolve também os
    # gateways de bridge (172.17.0.1 e afins), que não têm nada a ver com
    # gerência e só poluem o ALLOW_FROM. O IP de origem da rota default é o
    # endereço de gerência em praticamente todo nó PVE.
    NODE_IPS=$(ip route get 1.1.1.1 2>/dev/null | grep -oE 'src [0-9.]+' | awk '{print $2}')
    [ -n "$NODE_IPS" ] && ok "IP de gerência detectado: $NODE_IPS" \
                       || bad "não consegui detectar o IP — monte o ALLOW_FROM à mão"
fi

# ------------------------------------------------------------- ALLOW_FROM ---
hdr "ALLOW_FROM sugerido (passo 7)"

ALLOW="$WG_SUBNET"
for ip in $NODE_IPS; do ALLOW="$ALLOW,$ip"; done
ALLOW="$ALLOW,127.0.0.1"
printf '  ALLOW_FROM="%s"\n' "$ALLOW"
printf '  %sconfira antes de colar: nó faltando aqui = UI quebrada entre nós%s\n' "$DIM" "$RST"

# ---------------------------------------------------------------- pveproxy ---
hdr "pveproxy"

if [ -f /etc/default/pveproxy ]; then
    warn "/etc/default/pveproxy JÁ EXISTE — vai ser sobrescrito, guarde uma cópia:"
    printf '      cp /etc/default/pveproxy /root/pveproxy.default.bak\n'
    grep -E '^(ALLOW_FROM|DENY_FROM|POLICY|LISTEN_IP)' /etc/default/pveproxy 2>/dev/null \
        | sed 's/^/      atual: /'
else
    ok "/etc/default/pveproxy não existe — config nova, rollback = apagar o arquivo"
fi

systemctl is-active --quiet pveproxy && ok "pveproxy ativo" || bad "pveproxy NÃO está ativo"

# ------------------------------------------------------------- ferramentas ---
hdr "Ferramentas"

for pkg in wg fail2ban-client openssl; do
    command -v "$pkg" >/dev/null 2>&1 \
        && ok "$pkg presente" \
        || warn "$pkg ausente — instale antes do passo correspondente"
done

# --------------------------------------------------------------------- DNS ---
hdr "DNS e certificado"

RESOLVED=$(getent hosts "$FQDN" 2>/dev/null | awk '{print $1}' | head -1)
if [ -n "$RESOLVED" ]; then
    ok "$FQDN resolve para $RESOLVED"
    case "$RESOLVED" in
        10.99.*) ok "aponta para a sub-rede do túnel (correto)" ;;
        *)       warn "não é IP de túnel — confira o passo 2" ;;
    esac
else
    warn "$FQDN não resolve deste nó (esperado antes do passo 2)"
fi

CERT=/etc/pve/local/pve-ssl.pem
if [ -f "$CERT" ]; then
    SANS=$(openssl x509 -in "$CERT" -noout -text 2>/dev/null \
        | grep -A1 'Subject Alternative Name' | tail -1 | tr -d ' ')
    printf '  SAN atual: %s\n' "${SANS:-<vazio>}"
    printf '%s' "$SANS" | grep -q "$FQDN" \
        && ok "$FQDN já está no certificado" \
        || warn "$FQDN ainda NÃO está no SAN — passo 3"
fi

# ------------------------------------------------------------------ realms ---
hdr "Realms e TFA"

if command -v pveum >/dev/null 2>&1; then
    pveum realm list 2>/dev/null | sed 's/^/  /' \
        || warn "não consegui listar realms (precisa de root?)"
    printf '  %sTFA obrigatório se ajusta em Datacenter → Realms → Edit → Require TFA%s\n' "$DIM" "$RST"
else
    warn "pveum indisponível"
fi

# ------------------------------------------------------------------- resumo ---
hdr "Antes de seguir"

cat <<EOF
  1. Abra uma SEGUNDA sessão SSH e deixe aberta até o fim do passo 7.
  2. Guarde a linha ALLOW_FROM acima.
  3. Siga blue3-deploy/README.md NA ORDEM. O passo 7 é o único que tranca.
  4. Depois do passo 7, rode: bash blue3-deploy/verify.sh

EOF
