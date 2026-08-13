#!/bin/bash
# Verificação pós-blindagem — RODE NO NÓ, DEPOIS DO PASSO 7.
#
# ESTE SCRIPT NÃO ALTERA NADA. Só testa e reporta.
#
#   bash verify.sh
#
# Premissa que guia tudo aqui: **seu acesso continuar funcionando não prova que
# o bloqueio funciona** — prova só que você não se bloqueou. Por isso os testes
# que importam são os de recusa, não os de sucesso.

set -uo pipefail

RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; DIM=$'\e[2m'; RST=$'\e[0m'
ok()   { printf '  %s✓%s %s\n' "$GRN" "$RST" "$1"; PASS=$((PASS+1)); }
warn() { printf '  %s!%s %s\n' "$YLW" "$RST" "$1"; MANUAL=$((MANUAL+1)); }
bad()  { printf '  %s✗%s %s\n' "$RED" "$RST" "$1"; FAIL=$((FAIL+1)); }
hdr()  { printf '\n%s── %s %s\n' "$DIM" "$1" "$RST"; }

PASS=0; FAIL=0; MANUAL=0
FQDN="${FQDN:-pve.blue3.cloud}"

printf '\nVerificação — blindagem Blue3 Cloud\n'
printf '%sSomente leitura. Nada é alterado.%s\n' "$DIM" "$RST"

# ------------------------------------------------------------- wireguard ---
hdr "WireGuard"

if command -v wg >/dev/null 2>&1 && wg show 2>/dev/null | grep -q interface; then
    ok "interface WireGuard ativa"
    if wg show 2>/dev/null | grep -q "latest handshake"; then
        ok "handshake recente com pelo menos um peer"
    else
        warn "nenhum handshake ainda — suba o túnel do lado do admin"
    fi
    # chave compartilhada entre pessoas destrói a rastreabilidade do acesso
    PEERS=$(wg show 2>/dev/null | grep -c '^peer:')
    printf '  %speers configurados: %s (um por pessoa, nunca compartilhado)%s\n' \
        "$DIM" "$PEERS" "$RST"
else
    bad "WireGuard não está ativo — passo 1"
fi

# -------------------------------------------------------------- pveproxy ---
hdr "pveproxy / ALLOW_FROM"

if [ -f /etc/default/pveproxy ]; then
    ok "/etc/default/pveproxy existe"
    ALLOW=$(grep -E '^ALLOW_FROM' /etc/default/pveproxy 2>/dev/null | cut -d'"' -f2)
    printf '  ALLOW_FROM="%s"\n' "$ALLOW"

    # o erro que custa caro: nó do cluster faltando na lista
    if command -v pvecm >/dev/null 2>&1 && pvecm status >/dev/null 2>&1; then
        MISSING=""
        for ip in $(pvecm status 2>/dev/null \
            | awk '/^0x/ {for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print $i}' \
            | sort -u); do
            printf '%s' "$ALLOW" | grep -q "$ip" || MISSING="$MISSING $ip"
        done
        if [ -n "$MISSING" ]; then
            bad "nós do cluster FORA do ALLOW_FROM:$MISSING"
            printf '      %sa UI vai quebrar ao navegar para esses nós%s\n' "$DIM" "$RST"
        else
            ok "todos os nós do cluster estão no ALLOW_FROM"
        fi
    fi
else
    bad "/etc/default/pveproxy não existe — passo 7 não foi aplicado"
fi

systemctl is-active --quiet pveproxy && ok "pveproxy ativo" || bad "pveproxy inativo"

# ------------------------------------------------------------ certificado ---
hdr "Certificado"

CERT=/etc/pve/local/pve-ssl.pem
if [ -f "$CERT" ]; then
    END=$(openssl x509 -in "$CERT" -noout -enddate 2>/dev/null | cut -d= -f2)
    if openssl x509 -in "$CERT" -noout -checkend 604800 >/dev/null 2>&1; then
        ok "certificado válido (expira em $END)"
    else
        bad "certificado expira em menos de 7 dias ($END)"
    fi
    openssl x509 -in "$CERT" -noout -text 2>/dev/null \
        | grep -A1 'Subject Alternative Name' | grep -q "$FQDN" \
        && ok "$FQDN presente no SAN" \
        || bad "$FQDN AUSENTE do SAN — failover vai dar aviso de certificado"

    ISSUER=$(openssl x509 -in "$CERT" -noout -issuer 2>/dev/null)
    printf '%s' "$ISSUER" | grep -qi "let's encrypt" \
        && ok "emitido pela Let's Encrypt" \
        || warn "emissor não é Let's Encrypt: $ISSUER"
else
    bad "certificado não encontrado em $CERT"
fi

# ----------------------------------------------------------------- fail2ban ---
hdr "fail2ban"

if command -v fail2ban-client >/dev/null 2>&1; then
    if fail2ban-client status pve-blue3 >/dev/null 2>&1; then
        ok "jail pve-blue3 ativo"
        # jail que nunca casou nada é indistinguível de jail que funciona
        TOTAL=$(fail2ban-client status pve-blue3 2>/dev/null \
            | grep -i 'total failed' | grep -oE '[0-9]+$')
        if [ "${TOTAL:-0}" -eq 0 ]; then
            warn "jail com 0 matches — pode estar correto, ou o regex não casa nada"
            printf '      %serre uma senha de propósito e rode:%s\n' "$DIM" "$RST"
            printf '      fail2ban-regex /var/log/daemon.log /etc/fail2ban/filter.d/pve-blue3.conf\n'
        else
            ok "jail já casou $TOTAL tentativas — regex comprovadamente funciona"
        fi
    else
        bad "jail pve-blue3 não está ativo — passo 8"
    fi
else
    warn "fail2ban não instalado"
fi

# ------------------------------------------------------- testes manuais ---
hdr "Não dá para testar daqui"

cat <<EOF
  Estes três precisam ser feitos de FORA, e são os que realmente fecham o
  objetivo. Nenhum script rodando no próprio nó pode provar qualquer um deles.

  1. RECUSA de IP não listado — o teste que importa:
       curl -k --max-time 5 https://<ip-lan-nao-listado>:8006/
     Deve falhar. Se responder, o ALLOW_FROM não está valendo, e aí a
     semântica de POLICY é o primeiro suspeito (não foi possível verificá-la
     no ambiente de desenvolvimento).

  2. 8006 INALCANÇÁVEL da internet — teste de um link externo, celular no 4G
     serve. Este é o item que fecha o objetivo do projeto inteiro.

  3. NAVEGAÇÃO entre nós na UI, com o túnel de pé. É aqui que erro de
     ALLOW_FROM em cluster aparece — e o sintoma não aponta para o arquivo.

EOF

# ------------------------------------------------------------------ resumo ---
printf '%s──%s  %s%d ok%s · %s%d falha%s · %s%d manual%s\n\n' \
    "$DIM" "$RST" "$GRN" "$PASS" "$RST" "$RED" "$FAIL" "$RST" "$YLW" "$MANUAL" "$RST"

[ "$FAIL" -eq 0 ] || exit 1
