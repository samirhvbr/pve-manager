# Blue3 Cloud (fork do pve-manager) — Guia para Agentes de IA

Este documento orienta agentes de IA (Claude Code, etc.) que trabalham neste
repositório.

---

## 🔄 Antes de começar: `git pull`

**SEMPRE** verifique atualizações remotas antes de escrever ou alterar qualquer
coisa:

```bash
git pull
```

Trabalhar sobre uma base desatualizada gera conflitos. Para só inspecionar
antes: `git fetch && git status`.

---

## O que este repositório é

Um **fork white-label do `pve-manager`** (Proxmox VE 9.2.20) com a marca
**Blue3 Cloud**. Não é um projeto novo: é uma camada de personalização sobre um
upstream vivo, que continua recebendo commits.

**Isso muda como você escreve código aqui.** Toda alteração vai conflitar num
rebase futuro. A regra que governa tudo neste repo:

> **Minimize a superfície de conflito.** Prefira arquivo novo a patch em arquivo
> existente. Quando tiver que editar arquivo do upstream, edite o mínimo e
> deixe um comentário dizendo o que o upstream fazia ali.

---

## Comunicação

- **Idioma:** Português (pt-BR) para mensagens ao operador e documentação.
- **Identificadores de código:** Inglês (classes, métodos, variáveis).
- **Strings de UI:** passam por `gettext()` — mantenha em inglês, como o
  upstream. A tradução vem dos arquivos de locale.
- **Comentários no código:** inglês, para combinar com o código ao redor.

---

## Stack

| Camada        | Tecnologia                                      |
|---------------|-------------------------------------------------|
| Backend       | Perl 5 (`PVE/`, `bin/`)                         |
| Frontend      | ExtJS 7 (`www/manager6/`)                       |
| Empacotamento | Debian (`debian/`, `defines.mk`, `Makefile`)    |
| Lint JS       | `proxmox-biome` (`make check` / `make tidy`)    |
| Serviços      | `pveproxy`, `pvedaemon`, `pvestatd`, `pvescheduler` |

---

## Convenções do fork

### Assets de marca

Arquivos novos usam prefixo `blue3-` em `www/images/`
(`blue3-logo.png`, `blue3-icon-128.png`, `blue3-favicon.ico`). **Os arquivos do
upstream ficam intactos** — só as referências mudam. Fonte dos assets:
`blue3-logos/` na raiz.

### CSS

Cores da marca vivem em `www/css/blue3.css`, **arquivo separado**, nunca em
patch no `ext6-pve.css`. Ele é carregado por último no `index.html.tpl`, depois
do tema, para vencer por cascata.

Paleta: `#29ABE2` (ciano) · `#0071BC` (azul) · `#A1A0A0` (cinza).

> Não recolora seleção e hover de grid/tree num arquivo só: essas cores diferem
> entre o tema `crisp` e o `proxmox-dark`, e uma regra única quebra um dos dois.

### URLs externas

Centralizadas em `PVE.Utils` (`www/manager6/Utils.js`): `blue3SiteURL`,
`blue3DocsURL`, `blue3SupportURL`. Exceção: `noSubKeyHtml`, no mesmo object
literal, precisa da URL hardcoded (não dá para auto-referenciar).

### Comportamento removido do upstream

Onde você **remover** algo do upstream (ex.: as chamadas de
`Proxmox.Utils.checked_command()` que abrem o aviso de subscription), deixe um
comentário dizendo o que havia ali. Sem isso, o conflito de rebase vira um
enigma:

```js
// upstream calls Proxmox.Utils.checked_command() here to pop
// up the subscription notice; intentionally dropped
```

### Configuração de deploy

`blue3-deploy/` guarda a configuração de runtime dos nós (WireGuard, pveproxy,
fail2ban) — **não entra no build do .deb**. Diretório novo, que o upstream nunca
terá, então nunca conflita.

It also holds `web-redirect/web-redirect.sh`, which serves the UI on 80/443 and
is installed on every node, and `cluster/renumber-vms.sh`, which clears VMID
conflicts before a host joins. A new server follows
[docs/new-node.md](docs/new-node.md), which lists everything a node needs
beyond the stock PVE install.

---

## Limites do ambiente de desenvolvimento

Verificado em 13/08/2026 nesta máquina. **Não presuma que dá para rodar:**

| Ferramenta | Situação | Consequência |
|---|---|---|
| `proxmox-biome` | não instalado | `make check`/`make tidy` não rodam, e o build de `pvemanagerlib.js` depende do lint |
| `libpve-http-server-perl` | não instalado | não dá para verificar semântica de `ALLOW_FROM`/`POLICY` |
| `proxmox-widget-toolkit` | ausente | `proxmoxlib.js` não existe aqui; componentes `proxmox*` não podem ser inspecionados |
| `wireguard-tools` | não instalado | scripts de chave só validam lógica, não a criptografia |

**O que dá para validar:**

```bash
node --check www/manager6/<arquivo>.js     # sintaxe JS
perl -c PVE/<arquivo>.pm                   # sintaxe Perl
make -C www/images install DESTDIR=/tmp/x  # instalação de assets
bash -n <script>.sh                        # sintaxe shell
```

Quando não der para validar algo, **diga isso ao operador** em vez de afirmar
que está funcionando.

---

## Versionamento

`version.md` na raiz é a fonte da verdade, como nos outros projetos Blue3.
Formato: **`<upstream>+blue3.<N>`** — hoje `9.2.20+blue3.1`.

- **`<upstream>`** — a versão do Proxmox em que este fork está baseada. Muda só
  quando rebasear (`9.2.10` → `9.2.11`), e aí `<N>` volta para `1`.
- **`blue3.<N>`** — nosso contador. `N+1` a cada entrega do fork.

O `debian/changelog` do upstream **não é a nossa versão** — é a do Proxmox.

### Por que `+blue3.N` e não `blue3.N` puro

Verificado com `dpkg --compare-versions` em 13/08/2026:

| Esquema | Resultado |
|---|---|
| `blue3.1` | **sintaxe inválida** (`version number does not start with digit`) e sorteia acima de *toda* versão upstream — `9.2.11`, `9.3.0`, `10.0.0`. O apt nunca mais avisaria de um update do Proxmox, **incluindo correção de segurança**. |
| `9.2.10+blue3.1` | Válido. `> 9.2.10` (nosso build vence o pacote oficial) e `< 9.2.11` (o apt ainda avisa quando o Proxmox lança). |

O segundo é o único que preserva as duas propriedades que um fork de upstream
vivo precisa: o nosso pacote ganha do oficial, **e** continuamos vendo quando o
upstream se move.

Reproduza com:

```bash
dpkg --compare-versions "9.2.10+blue3.1" gt 9.2.10 && echo "vence o oficial"
dpkg --compare-versions "9.2.10+blue3.1" lt 9.2.11 && echo "ainda avisa do update"
```

### apt doesn't just report the upstream release, it installs it

Learned on 2026-09-21: an `apt upgrade` replaced `9.2.10+blue3.1` with the stock
`9.2.20` on both lab nodes, because nothing held the package. **Every node
running the fork must have `apt-mark hold pve-manager`.** With the hold, the new
upstream version still shows as *kept back*, so we still see it, but it no
longer reverts the fork silently. How to follow upstream (merge, build as
non-root, install, hold): [docs/upstream-sync.md](docs/upstream-sync.md).

---

## Documentação: `docs/` vs `.continue/`

Regra que divide os dois — **respeite ao escrever**:

| Diretório | Contém | Tempo verbal |
|---|---|---|
| `docs/` | O que **já está implementado** | passado / presente |
| `.continue/` | O que está **na lista de implantação** | futuro / pendente |

Quando terminar uma implantação, ela **migra**: sai da lista de pendências do
`.continue/` e vira documentação no `docs/`. Snapshot novo em
`.continue/README_AAAAMMDD.md`, nunca editando o anterior — o histórico datado é
o que mostra a evolução.

Não deixe uma frente descrita nos dois lugares. Se está no `docs/`, está pronto.

---

## COMMITTER — a skill cuida dos commits

**Existe `.committer.yml` na raiz deste repositório** — é o opt-in da skill
**COMMITTER**, que roda em ciclo (cron, via `~/x/GIT/run.sh`). Enquanto esse
arquivo existir com `enabled: true`, **commitar e pushar não é trabalho seu**.

**O que muda para você:**

- **Não commite nem pushe por padrão.** Conclua a entrega bumpando o
  `version.md` **e adicionando a entrada nova no topo do `CHANGELOG.md`**, e
  deixe a árvore pronta. É dali que a mensagem do commit sai — o changelog é o
  artefato de handoff entre você e a skill.
- **A entrada NÃO vai no `version.md`** (ADR-009 do skill-COMMITTER): esse
  arquivo é lido em runtime por vários repos da casa com
  `trim(file_get_contents())`, que devolve o arquivo inteiro — virar markdown
  quebraria a versão exibida em produção. `version.md` fica com a versão e
  nada mais; o título vai no `CHANGELOG.md`, primeiro da cadeia de busca
  (`CHANGELOG.md` → `docs/VERSION.md` → `version.md`).
- A skill monta `X.Y.Z - descrição`, commita e pusha a branch atual sozinha. Ela
  **nunca bumpa versão** (isso continua sendo julgamento seu) e nunca inventa
  mensagem: sem entrada de changelog ela cai num fallback Sonnet, e sem
  conseguir descrever com honestidade ela aborta e espera.

**Você ainda commita quando:**

- o Samir pedir explicitamente;
- a tarefa exigir o SHA na hora (deploy, abrir PR, referência cruzada);
- o `.committer.yml` sumir ou estiver `enabled: false` — aí vale o fluxo antigo,
  você bumpa, commita e pusha.

**Por que isso existe:** tirar de um modelo caro (Opus/Fable) o trabalho
mecânico de empacotar commit, que um Sonnet — ou, na maioria das vezes, nenhum
modelo — resolve. Economiza token e devolve tempo de desenvolvimento.

---

## AUDITOR — auditoria de documentação em ciclo

**Existe `.auditor/config.yml`** — opt-in da skill **AUDITOR**, que a cada ciclo
identifica o que mudou, verifica se está documentado e registra achados em
`.auditor/`.

- **`.auditor/` é versionado de propósito** (ADR-010) — não entra no
  `.gitignore`. O checkpoint precisa sobreviver a outra máquina.
- **Consequência direta:** relatório ali é artefato **publicado**. Neste repo
  isso importa mais que o normal, porque há chave WireGuard e token de
  Cloudflare em jogo. O `.gitignore` bloqueia os *arquivos*, mas o relatório é
  **texto gerado** — ele pode transcrever um segredo que leu. Ver
  [.auditor/README.md](.auditor/README.md).
- O AUDITOR documenta **sem alterar lógica da aplicação**.

⚠️ **Ainda não existe executor headless.** O `~/x/GIT/run.sh` só lista quem
optou; o ciclo roda por `/auditor` numa sessão do Claude Code.

---

## Checklist antes de entregar

- [ ] `node --check` nos arquivos JS alterados
- [ ] `perl -c` nos módulos Perl alterados
- [ ] Arquivos novos registrados no `Makefile` da pasta (`www/images/Makefile`,
      `www/css/Makefile`, `www/manager6/Makefile`)
- [ ] `make -C www/<pasta> install DESTDIR=/tmp/test` instala limpo
- [ ] Edição em arquivo do upstream tem comentário explicando o desvio
- [ ] **`version.md` bumpado e entrada nova no topo do `CHANGELOG.md`** — é o
      handoff para o COMMITTER; sem isso ele cai no fallback Sonnet
- [ ] Frente concluída **migrou** de `.continue/` para `docs/`
- [ ] `.continue/README_AAAAMMDD.md` novo se o estado do projeto mudou
- [ ] Nenhum segredo novo escapou do `.gitignore`:
      `git status --short | grep -iE 'key|conf|pem'`

---

## Documentos relacionados

- [README_br.md](README_br.md) — visão geral do fork
- [SECURITY.md](SECURITY.md) — diretrizes de segurança
- [docs/PROJETO.md](docs/PROJETO.md) — escopo e objetivos
- [docs/branding.md](docs/branding.md) — o que foi personalizado e onde
- [docs/upstream-sync.md](docs/upstream-sync.md) — following a new upstream
  release without losing the fork (merge, non-root build, `apt-mark hold`)
- [docs/new-node.md](docs/new-node.md) — checklist for adding a server to the
  cluster (fork + hold, web redirect, access)
- [docs/access.md](docs/access.md) — colleague accounts: one user, one pool,
  scoped ACLs, and what PVE cannot limit
- [docs/cluster.md](docs/cluster.md) — cluster members, the vote rule
  (physical host = 3, entry-point VM = 1) and the open router-NAT issue
- [docs/join-existing-host.md](docs/join-existing-host.md) — joining a host
  that already runs guests, without restarting any of them
- [docs/multi-tenancy.md](docs/multi-tenancy.md) — o que o PVE suporta de
  multi-tenancy (e o que não suporta)
- [blue3-deploy/README.md](blue3-deploy/README.md) — runbook de blindagem
- [.auditor/README.md](.auditor/README.md) — diretório do AUDITOR e o risco de
  segredo em relatório
- `version.md` — versão do fork (`<upstream>+blue3.<N>`)
- `.committer.yml` — opt-in do COMMITTER
- `.continue/` — o que está **na lista de implantação** (snapshots datados)
- `docs/` — o que **já está implementado**
