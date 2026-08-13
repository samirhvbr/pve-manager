#!/bin/bash
# Gera o par de chaves de um nó e dos peers admin do túnel de gerência.
#
#   ./gen-keys.sh pve01 samir joao
#
# Chave individual por pessoa, nunca compartilhada: é o que permite revogar
# uma pessoa sem rotacionar todo mundo, e é o que faz o `wg show` dizer quem
# está conectado.

set -euo pipefail

if [ $# -lt 2 ]; then
    echo "uso: $0 <nome-do-no> <admin> [admin...]" >&2
    exit 1
fi

command -v wg >/dev/null || { echo "instale o wireguard-tools primeiro" >&2; exit 1; }

NODE="$1"
shift

OUT="./keys-${NODE}"
mkdir -p "$OUT"
# As chaves privadas nascem aqui; nada de permissão frouxa nem por um instante.
chmod 700 "$OUT"
umask 077

gen() { # nome -> escreve .key/.pub e ecoa a pública
    wg genkey >"$OUT/$1.key"
    wg pubkey <"$OUT/$1.key" >"$OUT/$1.pub"
}

echo "==> nó: $NODE"
gen "node-$NODE"
printf '    pub: %s\n' "$(cat "$OUT/node-$NODE.pub")"

IP=101
for admin in "$@"; do
    echo "==> admin: $admin  (10.99.0.$IP)"
    gen "admin-$admin"
    # preshared key por peer: camada extra, barata, e protege contra
    # decriptação retroativa caso a criptografia assimétrica caia no futuro
    wg genpsk >"$OUT/psk-$admin.key"
    printf '    pub: %s\n' "$(cat "$OUT/admin-$admin.pub")"
    IP=$((IP + 1))
done

cat <<EOF

Chaves em $OUT/ (modo 700, arquivos 600).

Próximos passos:
  1. copie node-$NODE.key para o [Interface] PrivateKey do nó
  2. copie cada admin-*.pub e psk-*.key para os blocos [Peer] do nó
  3. entregue admin-<nome>.key + psk-<nome>.key à pessoa, por canal seguro
  4. APAGUE as chaves privadas dos admins desta máquina depois de entregar:
       shred -u $OUT/admin-*.key $OUT/psk-*.key

O passo 4 não é burocracia: enquanto essas chaves existirem aqui, esta máquina
vira um alvo que dá acesso ao plano de controle do cluster inteiro.
EOF
