# Blue3 Cloud

Fork white-label do **`pve-manager`** (Proxmox VE 9.2.20), com a marca
**Blue3 Cloud**.

🇺🇸 [English version](README.md)

---

> Documentação interna — não publicar. Este repositório gera um pacote Debian;
> `docs/`, `blue3-deploy/` e `blue3-logos/` são só de desenvolvimento e nunca
> são instalados pelo `make install`.
>
> Sempre escreva commits com boa descrição; o push é opcional, o commit
> organizado e documentado é obrigatório.

**Veja também:** [CLAUDE.md](CLAUDE.md) (convenções e guia para agentes) ·
[SECURITY.md](SECURITY.md) (segurança — revise sempre que o acesso ou a
exposição mudar) · [docs/PROJETO.md](docs/PROJETO.md) (escopo)

---

## O que é

Não é projeto novo: é uma camada de personalização sobre um **upstream vivo**,
que continua recebendo commits. Toda alteração aqui vai conflitar num rebase
futuro — por isso a regra que governa o repo é:

> **Minimize a superfície de conflito.** Prefira arquivo novo a patch em arquivo
> existente. Quando tiver que editar arquivo do upstream, edite o mínimo e deixe
> um comentário dizendo o que o upstream fazia ali.

---

## Stack

| Camada        | Tecnologia                                       |
|---------------|--------------------------------------------------|
| Backend       | Perl 5 (`PVE/`, `bin/`)                          |
| Frontend      | ExtJS 7 (`www/manager6/`)                        |
| Empacotamento | Debian (`debian/`, `defines.mk`, `Makefile`)     |
| Lint JS       | `proxmox-biome` (`make check` / `make tidy`)     |
| Serviços      | `pveproxy`, `pvedaemon`, `pvestatd`, `pvescheduler` |

---

## Estrutura

```
pve-manager/
├── PVE/                     # Backend Perl (API, serviços)
├── bin/                     # Executáveis (pveproxy, pvedaemon, ...)
├── www/
│   ├── index.html.tpl       # Template da página — título, favicons, CSS
│   ├── css/blue3.css        # ← Paleta Blue3 (arquivo só do fork)
│   ├── images/blue3-*       # ← Assets Blue3 (arquivos só do fork)
│   └── manager6/            # Aplicação ExtJS
├── blue3-logos/             # Fonte dos assets de marca (não entra no build)
├── blue3-deploy/            # ← Config de runtime dos nós + runbook
├── docs/                    # ← Documentação do projeto
├── .continue/               # ← Snapshots datados de estado
├── CLAUDE.md                # ← Guia para agentes de IA
└── SECURITY.md              # ← Diretrizes de segurança
```

Os itens marcados com ← não existem no upstream, então nunca geram conflito de
rebase.

---

## O que foi personalizado

| Área | Onde |
|------|------|
| Nome do produto | `www/index.html.tpl`, `Workspace.js`, `LoginWindow.js` |
| Logo e favicons | `www/images/blue3-*`, referenciados no `index.html.tpl` |
| Paleta | `www/css/blue3.css` (arquivo separado, carregado por último) |
| URLs externas | `PVE.Utils.blue3*URL` em `www/manager6/Utils.js` |
| Aviso de subscription | Removido em `Workspace.js` e `node/Summary.js` |

Detalhe completo em [docs/branding.md](docs/branding.md).

---

## Build

```bash
make check                          # lint JS (precisa do proxmox-biome)
make tidy                           # formatação JS
make deb                            # gera o pacote Debian
make -C www/images install DESTDIR=/tmp/test   # testa instalação de assets
```

### Limites do ambiente

Parte do ferramental **não está instalada** na máquina de desenvolvimento atual,
então pedaços do build não rodam localmente:

| Ferramenta | Impacto |
|------------|---------|
| `proxmox-biome` | `make check` / `make tidy` e o build de `pvemanagerlib.js` |
| `libpve-http-server-perl` | não dá para verificar semântica de `ALLOW_FROM` / `POLICY` |
| `proxmox-widget-toolkit` | componentes `proxmox*` não podem ser inspecionados |

O que funciona localmente:

```bash
node --check www/manager6/<arquivo>.js
perl -c PVE/<arquivo>.pm
bash -n <script>.sh
```

Quando não der para validar algo, **diga isso** em vez de afirmar que está
funcionando.

---

## Versionamento

`version.md` na raiz é a fonte da verdade, no formato
**`<upstream>+blue3.<N>`** — hoje `9.2.20+blue3.1`.

`<upstream>` é a release do Proxmox em que o fork está baseado; muda só no
rebase, e aí `<N>` volta para `1`. `<N>` incrementa a cada entrega do fork. O
`debian/changelog` do upstream é a versão do Proxmox, não a nossa.

O `+` não é enfeite — verificado com `dpkg --compare-versions`:

| Esquema | Comportamento |
|---------|---------------|
| `blue3.1` | **Sintaxe inválida** no Debian e sorteia acima de *toda* versão upstream — o apt nunca mais avisaria de um update do Proxmox, incluindo correção de segurança. |
| `9.2.10+blue3.1` | Válido. Maior que `9.2.10` (nosso build vence o oficial) e menor que `9.2.11` (o apt ainda avisa das releases upstream). |

Commits seguem `9.2.10+blue3.1 - descrição`, montados pela skill COMMITTER a
partir da entrada de changelog no `version.md`.

---

## Acesso e segurança

A interface web **não fica exposta à internet**. O acesso passa por um túnel
WireGuard dedicado, separado da VPN de uso geral.

Procedimento completo: [blue3-deploy/README.md](blue3-deploy/README.md).
Diretrizes: [SECURITY.md](SECURITY.md).
