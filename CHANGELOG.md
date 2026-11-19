# Changelog — Blue3 Cloud

A **versão** vive em [`version.md`](version.md), no formato
`<upstream>+blue3.<N>`. Este arquivo guarda só o título de cada entrega — é o
handoff para a skill COMMITTER, que monta `<versão> - <título>` a partir da
entrada nova no topo.

Entrada nova sempre **no topo**. Ver [CLAUDE.md](CLAUDE.md) para a convenção.

---

## 9.2.31+blue3.1 — Merge upstream pve-manager 9.2.31

**2026-11-19: the fork follows upstream to 9.2.31**

- Merged upstream bump commit `30a00e01` (9.2.31), 125 upstream commits after
  9.2.26.
  - Only `debian/changelog` conflicted.
  - Branding, Blue3 links and the removed subscription notice merged
    unchanged, and upstream added no new branding points under `www/`.
- Why now: upstream `libpve-storage-perl` 9.1.18 declares
  `Breaks: pve-manager (<< 9.2.29)`.
  - The nodes on 9.2.26+blue3.1 could not take that library or the others
    released with it, security fixes included.
  - spx3 had joined on stock 9.2.31.

## 9.2.26+blue3.1 — Merge upstream pve-manager 9.2.26

**2026-11-19: spx3 joins; the management-switch split**

The package is unchanged, so the version stays the same.

- spx3 joined with 3 votes, on a fresh install.
  - The cluster now has 5 hosts, 15 votes and quorum 8, so any two hosts can
    be down.
  - spx3 has the same three-port layout as pr9 and sgpu1, and a storage
    `spx3-ssd` on a RAID 1 of SSDs.
  - It runs stock `pve-manager` 9.2.31 on hold until the fork is synced.
- [docs/cluster.md](docs/cluster.md):
  - the five-host quorum table;
  - the 2–2 split of 2026-11-18: a management switch lost its unsaved
    configuration, and both halves of the cluster went read-only;
  - the one-side-only `pvecm expected` stopgap.
- [docs/new-node.md](docs/new-node.md):
  - do not `apt upgrade` a fresh node before the fork is held;
  - what to do when upstream is ahead of the fork. `libpve-storage-perl`
    9.1.18 breaks `pve-manager` older than 9.2.29.

**2026-11-17: pr9 and sgpu1 join the cluster**

The package is unchanged, so the version stays the same.

- Two more physical hosts joined with 3 votes each: the cluster has 12 votes,
  quorum 7, and any one host can now be down.
  - pr9 was a fresh install ([docs/new-node.md](docs/new-node.md)).
  - sgpu1 had one VM; it was renamed and its VM renumbered first
    ([docs/join-existing-host.md](docs/join-existing-host.md), *Second time:
    sgpu1*).
- [docs/new-node.md](docs/new-node.md), step 1: before a join, check the
  `/etc/hosts` entry, that only one MAC answers the host's IP, and that the
  clock is synchronized.
- [docs/cluster.md](docs/cluster.md): members table, the four-host quorum
  table, and the new hosts' bridges.
- [docs/cluster.md](docs/cluster.md), *Templates*: a copy of `blue3-debian` on
  every host (9201 spx1, 9202 pr9, 9203 sgpu1), because a template on local
  storage cannot be cloned to another host.
  [docs/access.md](docs/access.md) says what a colleague needs to clone them.
- New queue snapshot [.continue/README_20261117.md](.continue/README_20261117.md).

**2026-11-07**

- Merged upstream `pve-manager` 9.2.26 (bump commit `41a0e2e0`) into the fork,
  following [docs/upstream-sync.md](docs/upstream-sync.md). It carries the
  upstream fixes from 9.2.21 to 9.2.26. Among them:
  - `GET /pools?poolid=<pool>` checked `Pool.Audit` but ignored the result, so
    any user could list the members of every pool (9.2.23);
  - deleting a backup job by ID could delete another kind of job, such as a
    realm sync job (9.2.26);
  - line breaks are rejected in an interface's OVS options;
  - certificate management can be delegated on `/nodes/<node>/certificates`
    alone (9.2.26).
- Only `debian/changelog` conflicted. Branding, the Blue3 links and the
  removed subscription notice merged unchanged. Upstream added no new Proxmox
  strings or `checked_command()` calls under `www/`.
- Installed on both nodes on 2026-11-07, together with that day's security
  updates (kernel 7.0.14-28, QEMU 11.1.3, corosync 3.2.0), and each node was
  rebooted after its update. Both came back with the same guests running and the
  same ones stopped.
- [docs/upstream-sync.md](docs/upstream-sync.md), step 7: install the fork in
  the same apt transaction as the packages the hold keeps back. A plain
  `dpkg -i` left `pve-manager` unconfigured on spx1.
- [docs/cluster.md](docs/cluster.md): new section *Rebooting a host*, covering
  the `onboot` rule, snapshot rollbacks restoring `onboot`, and quorum while one
  host is down.

## 9.2.20+blue3.1 — Merge upstream pve-manager 9.2.20 and redeploy the fork

**2026-11-03: the web redirect also serves the backup server**

The package is unchanged, so the version stays the same.

- [`blue3-deploy/web-redirect/web-redirect.sh`](blue3-deploy/web-redirect/web-redirect.sh)
  now finds the UI by itself: 8006 when `pveproxy` is installed, 8007 when
  `proxmox-backup-proxy` is. On a PVE node it writes the same ruleset as
  before.
- It is installed on the cluster's new Proxmox Backup Server host. Checked
  from a workstation: plain HTTP gets a 301 to `https://<host>/`, and 443
  serves the PBS UI with the same certificate as 8007.

**2026-10-27: guests moving in from a standalone host, and `vmbr1`**

The package is unchanged, so the version stays the same. The changes are
node configuration and documentation.

- New [`docs/guest-migration.md`](docs/guest-migration.md). It covers the two
  methods tried for moving guests in from a standalone PVE 7.4 host:
  `qm remote-migrate` works but refuses snapshots and leaves the source
  locked, and backup/restore through a PBS is the one used for the bulk. It
  also covers the VMID rule (+1000 where free, else from 1140), the checks a
  copy needs before it starts, and the 2026-10-21 freeze of b3p1's storage. In
  that freeze, three parallel restores left an orphaned `lvcreate` holding the
  volume group lock, and `dmsetup udevcomplete` released it.
- **`vmbr1` on both nodes now matches the source host's bridge:** a plain
  bridge on `nic5` (the 10G card's second port, no link), comment
  `Telefonia`. It was created on 2026-10-23 as a port-less VLAN-aware bridge.
  It was rebuilt on 2026-10-27 with `ifdown`/`ifup vmbr1` only, while no guest
  was attached to it. See [`docs/cluster.md`](docs/cluster.md), *Bridges*.
- New [`blue3-deploy/network/vmbr1.sh`](blue3-deploy/network/vmbr1.sh)
  creates it on a new node. It is now step 5 of
  [`docs/new-node.md`](docs/new-node.md).
- spx1's stale pending network change, from 2026-09-21, was reverted. It
  only reordered `interfaces`.
- [`docs/access.md`](docs/access.md) now has the group's two grants from
  2026-10-21 (`PVEAuditor` on `/`, `PVEDatastoreAdmin` on `/storage`). It also
  explains why a deeper ACL, such as the group's `/nodes` entry, overrides
  `Administrator` on `/`. Because of that, the migration account can use any
  bridge but cannot create one.

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
