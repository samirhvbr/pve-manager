# Blue3 Cloud — Diretrizes de Segurança

**Versão:** 1.0
**Data:** 13/08/2026
**Escopo:** Fork do `pve-manager` e o acesso ao cluster Proxmox VE que ele serve.

---

## Por que este documento é conservador

O painel do PVE não é "mais um sistema web". É o plano de controle com poder
root sobre todas as VMs do ambiente — e, se o storage de backup for alcançável a
partir dele, sobre os backups também. Um comprometimento ali não é um incidente:
é perda total do parque virtualizado de uma vez.

Painéis de hypervisor expostos são alvo de varredura constante e automatizada,
justamente por esse retorno. **É o tamanho do estrago que justifica o rigor**,
não paranoia.

---

## Regras gerais (obrigatórias)

1. **Nunca commitar** chaves WireGuard, tokens de API (Cloudflare, ACME),
   certificados privados ou senhas. O `.gitignore` cobre os padrões conhecidos,
   mas confira antes do commit.
2. **A porta 8006 não vai para a internet.** Acesso só pelo túnel WireGuard de
   gerência. Ver [blue3-deploy/README.md](blue3-deploy/README.md).
3. **TOTP obrigatório no realm**, não por usuário — por usuário depende de cada
   pessoa lembrar de ativar.
4. **Chave WireGuard por pessoa**, nunca compartilhada. É o que permite revogar
   alguém sem rotacionar todo mundo, e o que faz o log dizer quem entrou.
5. **Contas nomeadas no dia a dia.** `root@pam` é break-glass, com TOTP e senha
   em cofre.
6. **Token de API com escopo mínimo.** Na Cloudflare, `API Token` restrito à
   zona — nunca a Global API Key, que dá acesso à conta inteira.

---

## Revogação de acesso

Verificado em `PVE/HTTPServer.pm:98`: o `check_user_enabled` roda em **toda
requisição autenticada**, dentro da verificação de ticket.

**Consequência prática:** desmarcar "Enabled" no usuário vale na próxima chamada
de API — segundos. Não é preciso esperar o ticket expirar (2h) nem reiniciar
serviço.

**Ressalva:** um console noVNC/SPICE **já aberto** é um websocket estabelecido.
Desabilitar o usuário barra novas requisições, mas não necessariamente derruba a
conexão em curso. Se precisar de certeza, encerre a sessão do console
explicitamente.

Para bloquear uma empresa inteira: remova a ACL do grupo em `/pool/<empresa>` —
uma ação, efeito imediato pelo mesmo mecanismo.

---

## Segurança no código do fork

### Não reintroduza exposição sem autenticação

`PVE/Service/pveproxy.pm` tem um bloco `pages` com o comentário do upstream:

```perl
# Note: there is no authentication for those pages and dirs!
```

São `/`, `/favicon.ico`, `/proxmoxlib.js` e `/qrcode.min.js`. **Não adicione
nada nesse bloco** sem entender que fica público para quem alcançar a porta.

### Cuidado com `html:` no ExtJS

A personalização usa `html:` para injetar o logo no cabeçalho
(`Workspace.js`). Isso é seguro porque a string é **estática e literal**. Se um
dia esse conteúdo passar a vir de configuração, API ou input, ele precisa ser
escapado — `html:` não escapa nada.

### Headers de real-IP

`PROXY_REAL_IP_HEADER` só pode ser habilitado junto com
`PROXY_REAL_IP_ALLOW_FROM`. Habilitar o header sem restringir quem pode
enviá-lo deixa qualquer cliente forjar o próprio IP de origem — e aí o fail2ban
bane o endereço que o atacante escolher, não o dele.

No desenho atual **não há reverse proxy**, então ambos ficam desligados.

---

## Multi-tenancy — o limite que precisa ser conhecido

Verificado em `PVE/API2/Pool.pm`: a criação de pool aceita **apenas `poolid` e
`comment`**. **O PVE não tem quota de recurso por pool ou tenant.**

- **Disco:** dá para capar de verdade, com storage dedicado por empresa (dataset
  ZFS, thin pool LVM, pool Ceph) + ACL em `/storage/<id>`. O limite é imposto
  pelo storage.
- **RAM e vCPU:** não dá para capar automaticamente. O controle é negar os
  privilégios de redimensionamento na role do tenant. Isso é ponto de controle,
  não quota — não existe um número que o sistema recuse ultrapassar.

**Implicação:** se o modelo comercial vender "empresa X tem 64 GB", o PVE não
faz isso cumprir sozinho. Detalhes em [docs/multi-tenancy.md](docs/multi-tenancy.md).

---

## Certificados

- ACME DNS-01 via Cloudflare — a validação **nunca precisa alcançar o nó**, que
  é o que torna certificado válido compatível com zero exposição.
- `pve.blue3.cloud` como SAN em **todos** os nós, para o failover não gerar
  aviso de certificado.
- **Monitore o vencimento.** Certificado vencido em painel de gerência costuma
  ser descoberto no pior momento.

---

## Checklist de revisão

Rode esta lista sempre que o acesso, a exposição ou o modelo de permissões mudar:

- [ ] 8006 não responde da internet — testado **de fora da rede**
- [ ] `ALLOW_FROM` inclui todos os nós do cluster (senão a UI quebra entre nós)
- [ ] Bloqueio testado de um IP que **deve** ser recusado — não presumido
- [ ] TOTP obrigatório no realm
- [ ] Nenhuma chave privada versionada (`git log -p --all -- '*.key'`)
- [ ] `fail2ban-regex` casa linhas reais do log
- [ ] Certificados válidos e com vencimento monitorado
- [ ] Nenhuma entrada nova no bloco `pages` do `pveproxy.pm`

---

## Pendências de verificação

Dois pontos que **não foi possível confirmar** no ambiente de desenvolvimento —
trate como não verificados até o teste passar:

1. **Semântica de `POLICY`** no `/etc/default/pveproxy`. O
   `libpve-http-server-perl` não está instalado. `allow` é a receita canônica do
   PVE, mas só o teste de bloqueio confirma.
2. **Formato do log de falha de senha** para o fail2ban. A linha vem do
   `pve-access-control`, fora deste repo. O que existe aqui —
   `PVE/HTTPServer.pm:89,101` — loga falha de *ticket* e **não traz o IP do
   cliente**, então não serve para o fail2ban.
