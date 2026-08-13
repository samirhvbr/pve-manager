# `.auditor/` — diretório de trabalho do AUDITOR

**Versionado de propósito** (ADR-010): o checkpoint precisa sobreviver a outra
máquina e a CI. Consequência direta — relatório aqui é artefato **publicado**,
então a redação de segredos é pré-requisito de qualquer execução, não opcional.

| Arquivo | Papel |
|---|---|
| `config.yml` | opt-in + configuração do ciclo |
| `state.json` | checkpoint (`last_sha`, `last_run`, `last_checked`, `reported[]`) |
| `index.md` | índice cumulativo dos ciclos — atualizado, nunca recriado |
| `reports/` | um relatório por ciclo com mudança (no-op não escreve) |
| `findings/` | lacunas e recomendações pendentes |

Nada aqui é escrito ainda: **não existe executor**. O `~/x/GIT/run.sh` lista
quem optou; o ciclo só roda por `/auditor` numa sessão do Claude Code.

---

## Atenção específica deste repositório

Este repo guarda configuração de acesso ao plano de controle de um cluster
Proxmox. Antes de qualquer ciclo que escreva relatório aqui, confirme que a
redação de segredos cobre:

- chaves e pré-chaves WireGuard (`blue3-deploy/wireguard/`)
- token de API da Cloudflare usado no ACME DNS-01
- IPs de LAN dos nós e a sub-rede do túnel de gerência

O `.gitignore` já bloqueia os arquivos, mas **relatório do AUDITOR é texto
gerado** — ele pode transcrever um segredo que leu, e aí o segredo entra no
repositório pela porta dos fundos. Ver [../SECURITY.md](../SECURITY.md).
