# Adding a server to the cluster

**Written:** 2026-09-25 · **Updated:** 2026-11-19 · **Applies to:** cluster `blue3-lab`

Checklist for a new node, in order. Each step links to the document with the
detail. Nothing here is packaged in the `.deb`. The node-side configuration
lives in [`blue3-deploy/`](../blue3-deploy/) and is applied per node.

---

## 1. Before installing PVE

- `hostname -f` returns the final name. **The PVE node name is fixed at
  install time.**
- `hostname -i` returns the management IP, not `127.0.1.1`. Check
  `/etc/hosts` by hand: the installer writes the IP the host had at install
  time. On 2026-11-17, pr9's entry pointed at its iDRAC's address, and sgpu1's
  at an old IP on another network.
- **Only one machine answers the IP.** Send ARP requests for it from a member
  and expect a single MAC. sgpu1 shared its address with its iDRAC, which
  showed up as a changed SSH host key.
- **The clock is synchronized.** A host without internet access gets no NTP.
  The office's AD domain controllers answer NTP; point chrony at them. pr9's
  clock was 3 h behind because its hardware clock held local time; write it
  back in UTC (`timedatectl set-local-rtc 0`, `hwclock --systohc --utc`).
- If the node was cloned from a template, regenerate `machine-id` and the SSH
  host keys. Detail: [lab.md](lab.md), *Preparação do SO*.

## 2. Join the cluster

A **physical host joins with 3 votes**. Target a physical member (b3p1), not
a VM that may run on the host being joined:

```bash
pvecm add 100.64.65.160 --votes 3
pvecm status | grep -E 'Quorate|Total votes'
corosync-cfgtool -s        # on EVERY node: every other node "connected"
```

Why 3 votes: [cluster.md](cluster.md). If the host **already runs guests**,
stop here and follow [join-existing-host.md](join-existing-host.md). The join
wipes the host's `/etc/pve`, VMIDs must be unique, and SSH keys disappear
until quorum. If any link shows *disconnected*, check for NAT on the path, as
described in [cluster.md](cluster.md) under *History*.

## 3. Install the fork, and hold it

Every node already has the current package in `/root/blue3-debs/`. Copy it
and check that the sha256 matches:

```bash
scp root@100.64.100.254:/root/blue3-debs/pve-manager_*_all.deb /tmp/
sha256sum /tmp/pve-manager_*_all.deb        # same hash on every node
scp /tmp/pve-manager_*_all.deb root@<new>:/root/blue3-debs/
ssh root@<new> 'dpkg -i /root/blue3-debs/pve-manager_*_all.deb && apt-mark hold pve-manager'
ssh root@<new> pveversion                   # pve-manager/<ver>+blue3.<N>/<commit>
```

**Without the hold, the next `apt upgrade` reverts the node to stock Proxmox.**
That happened on 2026-09-21. See [upstream-sync.md](upstream-sync.md).

**A fresh install has no hold.** Do not run `apt upgrade` on it before the fork
is installed. On 2026-11-19 a manual upgrade put stock 9.2.31 on spx3 before
its join.

### When upstream is ahead of the fork

Proxmox moves the libraries together with `pve-manager`. Once upstream is
ahead of the fork, the newest libraries refuse the fork. On 2026-11-19,
`libpve-storage-perl` 9.1.18 declared `Breaks: pve-manager (<< 9.2.29)`, while
the fork was 9.2.26+blue3.1. On a fresh node:

- `apt full-upgrade` with `pve-manager` held keeps those libraries back, and
  installing the fork together with their newest versions fails.
- **Install the fork with the exact versions an existing member runs.** Take
  them from `dpkg-query -W` on that member and pass them as `pkg=version`.
  Every version the cluster uses is still in the no-subscription repository.
- **If the node already has the newer stock packages,** do not downgrade 18
  packages. Join on stock, keep `pve-manager` held, and install the fork with
  the next upstream sync. Mixed minor versions in one cluster are normal
  during an upgrade. Check that `corosync` is the same on both sides.

The members already on the fork cannot take upstream updates of those
libraries either, security fixes included, until the fork is synced
([upstream-sync.md](upstream-sync.md)).

## 4. Web UI on 80/443

With the redirect, `100.64.x.x` typed in a browser opens the UI, without
`:8006`. From the workstation:

```bash
ssh root@<new> bash -s < blue3-deploy/web-redirect/web-redirect.sh

curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' http://<new>/   # 301 https://<new>/
curl -skL http://<new>/ | grep -o '<title>[^<]*'                         # <new> - Blue3 Cloud
```

How it works: a dedicated nft table (`inet blue3_web`) rewrites the
destination port of connections **addressed to the node itself** to 8006. The
`blue3-web-redirect.service` unit reloads the table at boot. pveproxy already
answers plain HTTP with a 301 to HTTPS, so port 80 needs nothing else.

The same script runs unchanged on a Proxmox Backup Server host. It finds
`proxmox-backup-proxy` instead of `pveproxy` and redirects to 8007, and that
daemon answers plain HTTP with the same 301.

Why not nginx: a reverse proxy makes every client appear as `127.0.0.1`,
which is in `ALLOW_FROM`. That would open the step 7 lockdown of the runbook,
and blind fail2ban. The redirect keeps the real source IP.

Things to know:

- **Firewall rules only need 8006.** The filter hooks run after the redirect
  and see the translated port.
- **ACME `http-01` standalone would break**, because port 80 goes to
  pveproxy. The runbook uses DNS-01, which is unaffected.
- Guest traffic is not touched. The rule matches only destination addresses
  that are local to the node (`fib daddr type local`).
- Undo it with `bash -s -- uninstall`, and inspect it with `bash -s -- status`.
- Verified on 2026-09-25 on all three nodes. Survival across a reboot has not
  been tested yet: the unit is enabled, but no node has rebooted since.

## 5. Bridges

Every node has `vmbr0` on its 10G port (the installer creates it, just make
sure it is called `vmbr0`) and `vmbr1`, the "Telefonia" bridge, on a port
with **no link**. Why they look like that: [cluster.md](cluster.md),
*Bridges*.

```bash
ssh root@<new> bash -s           < blue3-deploy/network/vmbr1.sh   # port nic5
ssh root@<new> bash -s -- <port> < blue3-deploy/network/vmbr1.sh   # if the spare port has another name
ssh root@<new> bash -s -- status < blue3-deploy/network/vmbr1.sh
```

The script refuses a port that has link, a port already in a bridge, and a
node with pending network changes in the UI. It brings up `vmbr1` only.

## 6. Access for people

Users, pools and ACLs live in `/etc/pve/user.cfg`, which the cluster
replicates. **Existing accounts work on the new node with no action.**

What is per node:

- **Storage.** Storage restricted with `nodes <name>` is local to that node. If
  colleagues should create VMs on the new node, grant its storages. See
  [access.md](access.md).
- **Bridges.** The ACL on `/sdn/zones/localnetwork/vmbr0` covers the bridge
  named `vmbr0` on **every** node. Name the new node's guest bridge `vmbr0`
  and existing grants apply. Name it differently and they do not.

## 7. Bookkeeping

- Add the node to the table in [lab.md](lab.md).
- Once the hardening runbook is in place, rerun
  [`preflight.sh`](../blue3-deploy/preflight.sh). `ALLOW_FROM` must list every
  node, or the UI breaks between nodes.
- Remote commands: prefix them with `LC_ALL=C`. The workstation forwards
  `pt_BR` locale variables, and a node without that locale floods every
  command with perl warnings.
