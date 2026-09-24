# Blue3 Cloud

White-label fork of **`pve-manager`** (Proxmox VE 9.2.20), rebranded as
**Blue3 Cloud**.

🇧🇷 [Versão em português](README_br.md)

---

> Internal documentation — do not publish. This repository builds a Debian
> package; `docs/`, `blue3-deploy/` and `blue3-logos/` are development-only and
> are never installed by `make install`.
>
> Always write commits with a good description; the push is optional, the
> organized, documented commit is mandatory.

**See also:** [CLAUDE.md](CLAUDE.md) (conventions and agent guide) ·
[SECURITY.md](SECURITY.md) (security — review whenever access or exposure
changes) · [docs/PROJETO.md](docs/PROJETO.md) (scope)

---

## What this is

Not a new project: a customization layer over a **live upstream** that keeps
receiving commits. Every change here will conflict on a future rebase, which is
why the governing rule is:

> **Minimize the conflict surface.** Prefer a new file over a patch to an
> existing one. When you must edit an upstream file, edit the minimum and leave
> a comment stating what upstream did there.

---

## Stack

| Layer      | Technology                                       |
|------------|--------------------------------------------------|
| Backend    | Perl 5 (`PVE/`, `bin/`)                          |
| Frontend   | ExtJS 7 (`www/manager6/`)                        |
| Packaging  | Debian (`debian/`, `defines.mk`, `Makefile`)     |
| JS lint    | `proxmox-biome` (`make check` / `make tidy`)     |
| Services   | `pveproxy`, `pvedaemon`, `pvestatd`, `pvescheduler` |

---

## Project structure

```
pve-manager/
├── PVE/                     # Perl backend (API, services)
├── bin/                     # Executables (pveproxy, pvedaemon, ...)
├── www/
│   ├── index.html.tpl       # Page template — title, favicons, CSS links
│   ├── css/blue3.css        # ← Blue3 palette (fork-only file)
│   ├── images/blue3-*       # ← Blue3 assets (fork-only files)
│   └── manager6/            # ExtJS application
├── blue3-logos/             # Brand asset source (not built)
├── blue3-deploy/            # ← Node runtime config + hardening runbook
├── docs/                    # ← Project documentation
├── .continue/               # ← Dated state snapshots
├── CLAUDE.md                # ← Guide for AI agents
└── SECURITY.md              # ← Security guidelines
```

Entries marked ← do not exist upstream, so they never cause rebase conflicts.

---

## What was customized

| Area | Where |
|------|-------|
| Product name | `www/index.html.tpl`, `Workspace.js`, `LoginWindow.js` |
| Logo and favicons | `www/images/blue3-*`, referenced from `index.html.tpl` |
| Palette | `www/css/blue3.css` (separate file, loaded last) |
| External URLs | `PVE.Utils.blue3*URL` in `www/manager6/Utils.js` |
| Subscription notice | Removed in `Workspace.js` and `node/Summary.js` |

Full detail in [docs/branding.md](docs/branding.md).

---

## Build

```bash
make check                          # JS lint (requires proxmox-biome)
make tidy                           # JS format
make deb                            # build the Debian package
make -C www/images install DESTDIR=/tmp/test   # test asset install
```

### Environment limits

Some tooling is **not installed** on the current development machine, so parts
of the build cannot run locally:

| Tool | Impact |
|------|--------|
| `proxmox-biome` | `make check` / `make tidy` and the `pvemanagerlib.js` build |
| `libpve-http-server-perl` | cannot verify `ALLOW_FROM` / `POLICY` semantics |
| `proxmox-widget-toolkit` | `proxmox*` components cannot be inspected |

What does work locally:

```bash
node --check www/manager6/<file>.js
perl -c PVE/<file>.pm
bash -n <script>.sh
```

---

## Versioning

`version.md` at the root is the source of truth, in the format
**`<upstream>+blue3.<N>`** — currently `9.2.20+blue3.1`.

`<upstream>` is the Proxmox release this fork is based on; it changes only on a
rebase, and `<N>` resets to `1`. `<N>` increments on each fork delivery.
Upstream's `debian/changelog` is Proxmox's version, not ours.

The `+` prefix is not cosmetic — verified with `dpkg --compare-versions`:

| Scheme | Behavior |
|--------|----------|
| `blue3.1` | **Invalid Debian syntax** and sorts above *every* upstream version, so apt would never report a Proxmox update again — security fixes included. |
| `9.2.10+blue3.1` | Valid. Greater than `9.2.10` (our build beats the official package) and less than `9.2.11` (apt still reports upstream releases). |

apt also *installs* those upstream releases unless the package is held, so
every node running the fork has `apt-mark hold pve-manager`. See
[docs/upstream-sync.md](docs/upstream-sync.md) for how to follow upstream.

Commits follow `9.2.10+blue3.1 - change description`, built by the COMMITTER
skill from the `version.md` changelog entry.

---

## Access and security

The web UI is **not exposed to the internet**. Access goes through a dedicated
WireGuard tunnel, separate from the general-purpose VPN.

Full procedure: [blue3-deploy/README.md](blue3-deploy/README.md).
Guidelines: [SECURITY.md](SECURITY.md).
