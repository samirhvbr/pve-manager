# Claude Code configuration — Blue3 Cloud (pve-manager fork)

## Model

**This repository does not choose the model** (repodocs ADR-027). The model is
the user's choice, made per session with `/model`, and a subagent inherits the
session's model. `.claude/settings.json` carries no `model`, no
`fallbackModel`, and nothing in `env` that steers one.

`effortLevel: xhigh` stays in the file — that is the highest level a settings
file accepts; `/effort max` raises it for a single session.

## Critical permissions

What this project has that the other Blue3 repos do not:

### Blocked (deny)

- **WireGuard keys** — `keys-*/`, `*.key`, `wg-mgmt.conf`. These are the keys
  that grant access to the cluster's control plane; no agent needs to read them.
- **`/etc/pve/**`** — the live cluster configuration. This repo is the *source*,
  not the production system.
- **`systemctl restart/stop pveproxy|pvedaemon`** — takes down the web interface
  for whoever is using it. If it is needed, the operator does it.
- **`qm destroy` / `pct destroy` / `pvesh delete`** — they destroy VMs and
  resources.
- **`apt install` / `dpkg -i`** — installing a package is the operator's call.

### Asks first (ask)

- **`make install`** without `DESTDIR` writes straight into
  `/usr/share/pve-manager`. With `DESTDIR=/tmp/...` it is allowed, because that
  is how the build gets tested.
- **`pvesh` / `pveum`** — the PVE API and user management. Reading is useful,
  writing needs approval.
- **`wg` / `wg-quick`** — they touch the management tunnel.

### Allowed

Syntax validation (`node --check`, `perl -c`, `bash -n`), lint
(`proxmox-biome`), search, and `make ... install DESTDIR=/tmp/*` to test
packaging without touching the system.

## Default mode

`plan` — this is a fork of a virtualization system in production. Seeing the
plan before the execution is worth the friction.
