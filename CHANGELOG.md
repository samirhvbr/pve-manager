# Changelog — Blue3 Cloud

A **versão** vive em [`version.md`](version.md), no formato
`<upstream>+blue3.<N>`. Este arquivo guarda só o título de cada entrega — é o
handoff para a skill COMMITTER, que monta `<versão> - <título>` a partir da
entrada nova no topo.

Entrada nova sempre **no topo**. Ver [CLAUDE.md](CLAUDE.md) para a convenção.

---

## 9.2.20+blue3.1 — Merge upstream pve-manager 9.2.20 and redeploy the fork

**2026-09-25: spx1 joins the cluster, and the vote rule**

The package is unchanged. Only the cluster changed, and nothing was
restarted: spx1's 11 running guests kept the same PIDs from before the join
until after the fork install.

- **Vote rule:** physical host = 3, entry-point VM = 1. b3p1 went from 1 to 3
  votes, and spx1 joined with `--votes 3`. The reason is that b3pve1 and
  b3pve2 are VMs 111 and 112 on spx1. With equal votes, a reboot of spx1
  would have left the cluster without quorum, and then no guest autostarts.
  See [`docs/cluster.md`](docs/cluster.md).
- **Renumbered on b3p1:** 100/101/102 → 200/201/202, to clear VMID conflicts
  with spx1. The running VMs were down for under a minute each. The
  colleague's template ACL moved to `/vms/200`. New
  [`blue3-deploy/cluster/renumber-vms.sh`](blue3-deploy/cluster/renumber-vms.sh)
  does this (`plan` first, then `run`).
- **spx1 joined with `--force`.** Its guest configs, 4 storages (restricted to
  spx1), an API token with its original secret, and a group were
  restored from a pre-join backup. Its local admin user was not migrated, on
  purpose. The unused Ceph (0 OSDs, 0 pools) was purged before the join. The
  node certificate that the join failed to generate was regenerated with
  `pvecm updatecerts --force`.
- **spx1 runs the fork** on hold, with the 80/443 redirect.
- **Named admin account** on the `pve` realm, with `Administrator` on `/`.
  `root@pam` stays as break-glass.
- **Router source NAT:** traffic from VLAN 1001 to spx1 arrives from the
  public address, so spx1 could not link with b3pve1 and b3pve2. See
  [`docs/cluster.md`](docs/cluster.md), *History*.
- **b3pve1 and b3pve2 were then removed from the cluster.** Any member
  serves the whole cluster's UI, so dedicated entry-point VMs added
  correlated votes and the NAT problem, and nothing else. Both were separated
  to standalone, then `pvecm delnode`, then their directories and root SSH
  keys were removed on both sides. The cluster is b3p1 + spx1: 6 of 6 votes,
  quorum 4.
- New docs: [`docs/cluster.md`](docs/cluster.md) and
  [`docs/join-existing-host.md`](docs/join-existing-host.md).

**2026-09-25: web UI on 80/443, and the first colleague account**

The package is unchanged, so the version stays the same. Both changes are
node-side configuration.

- New [`blue3-deploy/web-redirect/web-redirect.sh`](blue3-deploy/web-redirect/web-redirect.sh),
  installed on all three nodes. It adds an nft table that redirects
  connections addressed to the node on 80 and 443 to 8006, plus a unit that
  reloads it at boot. Typing the bare IP in a browser now opens the UI. It is a
  port redirect rather than nginx so that pveproxy keeps seeing real client
  IPs: behind a proxy, everyone would be `127.0.0.1`, which `ALLOW_FROM`
  allows. Not tested yet: surviving a reboot.
- First colleague account on the `pve` realm, with its own pool and ACLs
  scoped to the pool, three storages, `vmbr0` and the `blue3-debian`
  template. Verified by logging in as the colleague: they could create, turn
  into a template, clone and destroy in their pool, and got 403 on everything
  outside it.
- New docs: [`docs/new-node.md`](docs/new-node.md), the checklist for adding a
  server, and [`docs/access.md`](docs/access.md), the colleague-account recipe.

An `apt upgrade` on the `blue3-lab` nodes replaced `9.2.10+blue3.1` with the
stock `pve-manager 9.2.20`, since `9.2.10+blue3.1 < 9.2.20` and nothing held the
package. That ordering is by design (apt must keep seeing upstream releases),
so the fix is to follow upstream, not to fight the version scheme.

- Merged upstream `49318c67` (bump version to 9.2.20, 116 commits) into the
  fork. Merged rather than rebased, so `master` history is not rewritten.
- Only two fork-touched files moved upstream: `debian/changelog` (conflict,
  resolved by stacking the fork entries) and `www/manager6/Utils.js`
  (auto-merged, Blue3 URLs intact).
- No new subscription-nag or Proxmox-branding spots were introduced upstream.
- `pve-manager` is now on `apt-mark hold` on the nodes, so the next
  `apt upgrade` lists it as kept back instead of silently reverting the fork.

**Deployed and verified (b3pve1, b3pve2)**

- `make check`: biome over 376 files and all Perl tests pass. `lintian` shows
  only the upstream groff man-page warnings.
- The build must run as a non-root user. As root, upstream's
  `CephKeyMigrationScript_test.pl` fails tests 375 and 376, which expect a
  *must run as root* refusal.
- Both nodes report `pve-manager/9.2.20+blue3.1/cdabba49`, serve
  `<title><node> - Blue3 Cloud</title>`, answer HTTP 200 for the Blue3 assets,
  and stay quorate.
- The third cluster member `b3p1` (physical, running guests) got the same
  package, same sha256, and the same hold. Its guests kept running through
  the install. All three nodes report `repoid cdabba49`.
- New: [`docs/upstream-sync.md`](docs/upstream-sync.md), the procedure for the
  next upstream release.

## 9.2.10+blue3.1 — personalização inicial da marca e blindagem de acesso

Primeira entrega do fork, sobre o pve-manager 9.2.10.

**Marca (implementado)**

- Produto renomeado para **Blue3 Cloud**: título da aba, janela de login,
  cabeçalho e texto de versão
- Logo, favicons e apple-touch-icon próprios (`www/images/blue3-*`), com os
  arquivos do upstream deixados intactos — só as referências mudaram
- Paleta `#29ABE2`/`#0071BC` em `www/css/blue3.css`, arquivo separado carregado
  por último para vencer o tema por cascata
- URLs externas centralizadas em `PVE.Utils.blue3*URL`
- Aviso de subscription removido no pós-login e em "Package versions"

**Acesso (especificado, não aplicado)**

- Runbook de blindagem em `blue3-deploy/`: WireGuard dedicado, Let's Encrypt via
  Cloudflare DNS-01, TOTP obrigatório no realm, lockdown do `pveproxy`, fail2ban
- `preflight.sh` e `verify.sh`, somente-leitura, seguros em produção
- **Nada foi aplicado em nó real ainda**

**Padrões de projeto**

- `CLAUDE.md`, `README.md`/`README_br.md`, `SECURITY.md`, `docs/`, `.continue/`,
  `.claude/`, `version.md`, `.committer.yml`, `.auditor/`
- Versionamento `<upstream>+blue3.<N>` — `blue3.N` puro é sintaxe Debian
  inválida e sorteia acima de toda versão upstream, o que esconderia updates de
  segurança do Proxmox
- `.gitignore` testado (13 casos): bloqueia chave WireGuard independente do nome
  do arquivo, sem quebrar os `.conf` do upstream; corta 31 MB de template
  AngularJS de `blue3-logos/`

**Não validado nesta entrega**

- `make check` não rodou — `proxmox-biome` ausente. Validação foi `node --check`
- Semântica de `POLICY` no `pveproxy` não verificada — `libpve-http-server-perl`
  ausente
- Regex do fail2ban não confirmado contra log real
- Caminho de cluster do `preflight.sh` nunca rodou contra cluster de verdade
