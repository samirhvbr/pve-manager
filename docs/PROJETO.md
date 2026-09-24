# Blue3 Cloud — Escopo do Projeto

**Última atualização:** 13/08/2026

---

## Objetivo

Transformar o `pve-manager` (Proxmox VE 9.2.20) num produto white-label
**Blue3 Cloud**, publicado em `pve.blue3.cloud`, com acesso restrito e — no
médio prazo — capacidade de vender frações do cluster para empresas clientes que
gerenciam os próprios usuários.

## O que este projeto não é

Não é um sistema novo nem um wrapper. É um **fork de um upstream vivo**. O
Proxmox continua lançando versões, e cada uma vai precisar de rebase. Isso é a
restrição central de arquitetura, não um detalhe:

> Toda decisão neste projeto é avaliada por quanto conflito ela cria no próximo
> rebase.

Daí as convenções: arquivo novo em vez de patch, prefixo `blue3-` nos assets,
CSS separado, e comentário obrigatório onde comportamento do upstream foi
removido.

---

## Estado por frente

### 1. Marca — **implementado**

Nome do produto, logo, favicons, paleta, títulos e links externos. O aviso de
subscription foi removido. Detalhe em [branding.md](branding.md).

Pendente: decidir o domínio dos links da UI (`blue3.com.br` vs `blue3.cloud` —
hoje estão inconsistentes) e redirecionar os botões de ajuda por painel, que
exigem o `proxmox-widget-toolkit`.

### 2. Acesso e segurança — **especificado, não aplicado**

Runbook completo em [../blue3-deploy/README.md](../blue3-deploy/README.md):
WireGuard dedicado, DNS interno, Let's Encrypt via Cloudflare DNS-01, TOTP
obrigatório, lockdown do `pveproxy`, fail2ban.

Os arquivos de configuração estão prontos. **Nada foi aplicado em nó real
ainda.**

### 3. Multi-tenancy — **analisado, não implementado**

Análise verificada em [multi-tenancy.md](multi-tenancy.md).

Resumo: três dos quatro requisitos do Samir são atendidos nativamente pelo PVE
(revogação rápida, delegação por empresa, bloqueio granular). O quarto — **quota
de RAM/vCPU por empresa — não existe no PVE** e precisa ser construído por fora
se o modelo comercial depender disso.

---

## Decisões tomadas

| Data | Decisão | Motivo |
|------|---------|--------|
| 13/08/2026 | Nome do produto: **Blue3 Cloud** | Marca própria, sem menção a Proxmox na UI |
| 13/08/2026 | CSS da marca em arquivo separado | Rebase com upstream fica barato |
| 13/08/2026 | Assets com prefixo `blue3-`, upstream intacto | Só as referências mudam |
| 13/08/2026 | **Não** expor a 8006 à internet | Raio de explosão: perda total do parque |
| 13/08/2026 | WireGuard dedicado, separado do da Ubiquiti | O da Ubiquiti atende suporte e N3; alcance ao hypervisor não deve vir junto com VPN de uso geral |
| 13/08/2026 | Um túnel WireGuard por nó, sem hub | Sem ponto único de falha — acesso sobrevive à queda do nó de entrada |
| 13/08/2026 | TOTP (não WebAuthn) | Escolha do operador; aceitável porque a 8006 só é alcançável pelo túnel |
| 13/08/2026 | `pve.blue3.cloud` → IP do túnel, não da LAN | Mantém `AllowedIPs` mínimo, sem rotear a LAN para dentro do WG |
| 13/08/2026 | Versão do fork em `version.md`, formato `<upstream>+blue3.<N>` | `blue3.N` puro é sintaxe Debian inválida e sorteia acima de toda versão upstream — o apt nunca mais avisaria de update do Proxmox. Verificado com `dpkg --compare-versions` |
| 13/08/2026 | `.gitignore` do WireGuard por **diretório**, não por nome | Config de WG é só um `.conf` e o nome varia; e `*.conf` amplo sumiria com 4 `.conf` legítimos do upstream |
| 13/08/2026 | `autoMode.allow` estreito para `.claude/settings.json` | O classificador é camada separada de `permissions`; regra ampla ali desligaria o classificador na prática |
| 13/08/2026 | COMMITTER e AUDITOR habilitados | Padrão dos demais repositórios Blue3 |
| 13/08/2026 | `docs/` = implementado · `.continue/` = a implantar | Separação pedida pelo operador; frente concluída migra de um para o outro |

### 4. Padrões de projeto — **implementado**

`CLAUDE.md`, `README.md`/`README_br.md`, `SECURITY.md`, `docs/`, `.continue/`,
`.claude/`, `version.md`, `.committer.yml`, `.auditor/` — seguindo a convenção
dos demais repositórios Blue3 (`AREA81`, `EOP`), adaptada ao stack
Perl/ExtJS/Debian.

`.gitignore` estendido e **testado** (13 casos): bloqueia chave WireGuard
independente do nome do arquivo, sem quebrar os `.conf` do upstream.

---

## Decisões em aberto

| Assunto | Pergunta | Bloqueia |
|---------|----------|----------|
| Domínio | `blue3.com.br` ou `blue3.cloud` nos links da UI? | Release |
| Quota de recursos | Controlar dimensionamento manualmente ou construir contabilidade no fork? | Modelo comercial |
| Docs | Existe/existirá `docs.blue3.*`? Os botões de ajuda apontam para lá? | Links da UI |
| `blue3-logos/` | Reduzir aos PNGs de marca ou ignorar? (33 MB) | Primeiro commit |

---

## Próximos passos

Mantidos em [`.continue/`](../.continue/) — é lá que vive a lista de
implantação. O resumo: aplicar o runbook num nó destrava todas as outras
frentes.
