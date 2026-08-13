# Blue3 Cloud — hardening de acesso ao PVE

Runbook para publicar `pve.blue3.cloud` **sem expor a porta 8006 à internet**.

Decisões tomadas em 13/08/2026:

| # | Item | Decisão |
|---|------|---------|
| 1 | Acesso | WireGuard dedicado, separado do WG da Ubiquiti |
| 2 | DNS | `pve.blue3.cloud` → IP interno, pelo DNS interno |
| 3 | Certificado | Let's Encrypt via ACME DNS-01 na Cloudflare |
| 4 | 2FA | TOTP obrigatório no realm |
| 5 | Contas | Usuários nomeados; `root@pam` como break-glass |

Topologia: **cluster** (não nó único) — isso muda o passo 7, leia o aviso lá.

---

## A ordem importa

Faça na sequência. O princípio: **estabeleça o caminho seguro e comprove que
ele funciona antes de fechar qualquer porta.** Inverter isso é como se trancar
do lado de fora — e num hypervisor o custo de recuperar é uma ida ao datacenter.

O passo 7 (travar o `pveproxy`) é o único capaz de te deixar sem acesso à UI.
Ele é o último de propósito, e tem um aviso próprio.

---

## 0. Preflight

Antes de qualquer coisa, **no nó**:

```bash
bash blue3-deploy/preflight.sh
```

Somente leitura — não altera nada, pode rodar em produção quantas vezes quiser.

Ele monta a linha **`ALLOW_FROM` pronta a partir do cluster real** (lendo
`corosync.conf`, com `pvecm` de reserva). Esse é o valor que, errado, quebra a
UI entre nós no passo 7 com um sintoma que não aponta para o arquivo certo —
melhor deixar a máquina montar do que digitar de memória.

Também avisa se `/etc/default/pveproxy` já existe (vai ser sobrescrito), quais
ferramentas faltam, e o estado atual de DNS e certificado.

---

## 1. WireGuard de gerência

Túnel dedicado, **separado do WG da Ubiquiti**. O da Ubiquiti atende suporte e
N3; alcance ao plano de controle do hypervisor não deve vir junto com VPN de
uso geral. Se um dia uma credencial de suporte vazar, o estrago para no que o
suporte precisa acessar — e não chega no hypervisor.

Porta **51821**, para não colidir com a 51820 da Ubiquiti.

```bash
apt install wireguard-tools
cd blue3-deploy/wireguard
./gen-keys.sh pve01 samir joao        # uma chave por pessoa, nunca compartilhada
```

Preencha `wg-mgmt.conf.example` → `/etc/wireguard/wg-mgmt.conf` no nó
(`chmod 600`), e `peer-admin.conf.example` no cliente. Depois:

```bash
systemctl enable --now wg-quick@wg-mgmt
wg show                                # deve listar os peers
```

**Endereçamento:** nós em `10.99.0.11-13`, admins a partir de `10.99.0.101`.

**Um túnel por nó, de propósito.** O admin sobe o túnel do nó que quer acessar.
Parece menos elegante que um hub único, mas não tem ponto único de falha: se o
nó de entrada cair, você troca de túnel e continua com acesso ao cluster —
que é exatamente o momento em que você mais precisa dele.

> Alternativa de menor manutenção, se preferirem depois: uma segunda interface
> WG na própria Ubiquiti, com peer group separado e regra de firewall liberando
> só a 8006. Consegue a mesma separação sem serviço novo no hypervisor.

### Valide antes de seguir

```bash
wg show                                # handshake recente?
curl -k https://10.99.0.11:8006/       # responde pelo túnel?
```

Só avance quando isso funcionar.

---

## 2. DNS interno

No servidor DNS de vocês, na zona interna:

```
pve.blue3.cloud.     A    10.99.0.11     # IP do túnel do nó de entrada
pve01.blue3.cloud.   A    10.99.0.11
pve02.blue3.cloud.   A    10.99.0.12
pve03.blue3.cloud.   A    10.99.0.13
```

Apontar para o **IP do túnel** (e não para o IP de LAN) mantém o desenho
mínimo: o `AllowedIPs` do cliente fica só em `10.99.0.0/24`, sem rotear a LAN
de gerência para dentro do WireGuard. Menos alcance no túnel, menos estrago se
uma chave vazar.

O `DNS =` no config do cliente precisa apontar para o DNS interno — senão o
nome não resolve com o túnel de pé e o certificado não valida.

**Failover:** se o nó de entrada cair, mude o A de `pve.blue3.cloud` para outro
nó e suba o túnel correspondente. Por isso o passo 3 coloca `pve.blue3.cloud`
como SAN no certificado de **todos** os nós.

---

## 3. Let's Encrypt via Cloudflare (DNS-01)

**O ponto que confunde:** o DNS interno resolvendo `pve.blue3.cloud` não ajuda
em nada o Let's Encrypt. A validação DNS-01 exige um TXT em
`_acme-challenge.pve.blue3.cloud` na zona **pública autoritativa** do
`blue3.cloud`, na Cloudflare. São duas coisas separadas e você precisa das duas:
o A interno (para vocês chegarem) e o TXT público (para a LE validar).

A boa notícia: como é DNS-01, a LE **nunca precisa alcançar o nó**. É o que
torna certificado válido compatível com zero exposição.

### Token da Cloudflare

Crie um **API Token** (não a Global API Key) com escopo mínimo:

- `Zone → DNS → Edit`
- `Zone → Zone → Read`
- **Zone Resources:** apenas `blue3.cloud`

A Global Key dá acesso à conta inteira; se vazar do nó, vocês perdem todos os
domínios, não só este.

### No PVE

`Datacenter → ACME`:

1. **Accounts → Add** — e-mail de contato, ToS aceito
2. **Challenge Plugins → Add** — tipo `DNS`, API `cloudflare`, campo `CF_Token`

Depois, **em cada nó**, `Node → Certificates → ACME`:

3. **Add** o domínio do nó (`pve01.blue3.cloud`), plugin = o criado acima
4. **Add** também `pve.blue3.cloud` como domínio adicional — é o que permite o
   failover do passo 2 sem aviso de certificado
5. **Order Certificates Now**

A lista de provedores é carregada dinamicamente de
`/cluster/acme/challenge-schema` (confirmado em `ACMEAPISelector.js`), então
`cloudflare` aparece na combo.

A renovação é automática, mas **monitore**: certificado vencido em painel de
gerência costuma ser descoberto no pior momento.

---

## 4. TOTP obrigatório no realm

`Datacenter → Realms → <realm> → Edit → Require TFA = OATH/TOTP`

Confirmado em `www/manager6/form/TFASelector.js:84-89` — o campo se chama
literalmente "Require TFA" e oferece None / OATH/TOTP / Yubico.

Fazer no **realm** e não por usuário é o ponto: por usuário, você depende de
cada pessoa lembrar de ativar. No realm, é obrigatório para todo mundo, agora e
para quem entrar depois.

Cada usuário cadastra o próprio TOTP no menu do usuário → **TFA**.

> Nota honesta sobre TOTP: ele é *phishable*. Um proxy reverso malicioso captura
> o código e reusa dentro da janela de validade. WebAuthn (passkey ou chave
> física) não cai nisso, porque é ligado à origem. Com o 8006 alcançável só pelo
> WireGuard, o risco de phishing cai bastante — o atacante teria que estar
> dentro do túnel. Então TOTP aqui é uma escolha defensável. Se um dia abrirem
> mais o acesso, revisitem isto primeiro.

---

## 5. Contas nomeadas, `root@pam` como break-glass

**`root@pam` não pode ser removido** — confirmado em `www/manager6/dc/UserView.js:32`,
onde ele é explicitamente excluído do botão de remoção. É a conta break-glass do
PVE, por desenho. Então o objetivo não é eliminá-la, é tirá-la do uso diário:

1. `Datacenter → Permissions → Users` — crie um usuário nomeado por pessoa
2. Dê `Administrator` no path `/` a quem precisa
3. **Cadastre TOTP em cada um**, inclusive no `root@pam`
4. Senha longa e aleatória no `root@pam`, guardada em cofre — não na cabeça de
   ninguém e não em planilha
5. Dia a dia só com conta nomeada

O ganho concreto é rastreabilidade: com todo mundo entrando como `root`, o log
de tarefas não responde "quem apagou esta VM?". Com conta nomeada, responde.

---

## 6. Firewall do PVE

`Datacenter → Firewall` — regra de entrada permitindo 8006 apenas de
`10.99.0.0/24` e dos IPs de LAN dos nós do cluster.

Cinto e suspensório junto com o passo 7: são mecanismos independentes, e é
justamente por isso que valem os dois.

---

## 7. Travar o `pveproxy` — POR ÚLTIMO

> ### Pare e leia
>
> Este passo é o único que pode te trancar fora da interface web.
>
> - Faça com **SSH ou console físico já aberto**
> - **Não feche** essa sessão até confirmar que o login web funciona
> - Rollback: apague `/etc/default/pveproxy` e `systemctl restart pveproxy`

Copie `pveproxy/pveproxy.default` → `/etc/default/pveproxy` e preencha os IPs.

```bash
systemctl restart pveproxy
```

### Cluster: o erro que custa caro

O `pveproxy` encaminha chamadas de API **entre nós** pela própria 8006. Se os
IPs dos outros nós não estiverem no `ALLOW_FROM`, o login funciona normalmente
e a UI só quebra ao navegar para outro nó — um sintoma que não aponta para cá.
Você vai procurar em corosync, em rede, em tudo menos no arquivo certo.

Inclua sempre: sub-rede do WG + IP de LAN de **todos** os nós + `127.0.0.1`.

### Verifique de verdade

```bash
bash blue3-deploy/verify.sh
```

Confere WireGuard, `ALLOW_FROM` (inclusive se **algum nó do cluster ficou de
fora**), certificado, SAN e fail2ban. Sai com código 1 se algo falhou.

Mas atenção ao que ele **não** consegue provar: seu acesso continuar
funcionando **não prova** que o bloqueio funciona — prova só que você não se
bloqueou. Nenhum script rodando no próprio nó fecha isso. Teste os dois lados
à mão:

```bash
# de dentro do túnel: deve responder
curl -k https://10.99.0.11:8006/

# de um IP que DEVE ser bloqueado: deve falhar
curl -k --max-time 5 https://<ip-lan-nao-listado>:8006/

# navegue entre os nós na UI -- é aqui que erro de cluster aparece
```

Não consegui verificar a semântica exata de `POLICY` (o `libpve-http-server-perl`
não está instalado na máquina onde isto foi escrito). `allow` é a receita
canônica do PVE, mas trate como não verificado até o teste acima passar.

---

## 8. fail2ban

```bash
apt install fail2ban
cp fail2ban/pve-blue3-filter.conf /etc/fail2ban/filter.d/pve-blue3.conf
cp fail2ban/pve-blue3-jail.conf   /etc/fail2ban/jail.d/pve-blue3.conf
```

**Valide o regex antes de confiar nele:**

```bash
# erre uma senha de propósito na UI, depois:
grep -i "authentication failure" /var/log/daemon.log | tail -5
fail2ban-regex /var/log/daemon.log /etc/fail2ban/filter.d/pve-blue3.conf
```

Se `Matched` vier zero, ajuste o `failregex` ao formato real. **Um jail que não
casa nada falha em silêncio** e dá falsa sensação de proteção — pior que não ter
jail nenhum.

Por que isto precisa de validação: a linha de falha de senha vem do
`pve-access-control`, pacote fora do repositório do `pve-manager`, então não deu
para ler o formato exato. O que existe *neste* repo é outra coisa —
`PVE/HTTPServer.pm:89,101` emite `"authentication failure: ..."` para
ticket/token inválido, e essa linha **não traz o IP do cliente**, então não
serve para o fail2ban.

---

## Checklist final

- [ ] `wg show` mostra handshake
- [ ] `pve.blue3.cloud` resolve para o IP do túnel
- [ ] Cadeado verde, sem aviso de certificado
- [ ] Certificado tem `pve.blue3.cloud` como SAN em **todos** os nós
- [ ] Login exige TOTP
- [ ] `root@pam` com TOTP e senha em cofre
- [ ] Navegação entre nós do cluster funciona **depois** do passo 7
- [ ] Acesso de IP não listado é recusado (testado, não presumido)
- [ ] `fail2ban-regex` casa linhas reais
- [ ] 8006 **não** responde da internet — confirme de fora da rede

O último item é o que fecha o objetivo. Vale testar de um link externo, não de
dentro da rede de vocês.
