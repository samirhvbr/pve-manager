# Adding a server to the cluster

**Written:** 2026-09-25 · **Applies to:** cluster `blue3-lab` (b3p1, spx1)

Checklist for a new node, in order. Each step links to the document with the
detail. Nothing here is packaged in the `.deb`. The node-side configuration
lives in [`blue3-deploy/`](../blue3-deploy/) and is applied per node.

---

## 1. Before installing PVE

- `hostname -f` returns the final name. **The PVE node name is fixed at
  install time.**
- `hostname -i` returns the management IP, not `127.0.1.1`.
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

## 5. Access for people

Users, pools and ACLs live in `/etc/pve/user.cfg`, which the cluster
replicates. **Existing accounts work on the new node with no action.**

What is per node:

- **Storage.** Storage restricted with `nodes <name>` is local to that node. If
  colleagues should create VMs on the new node, grant its storages. See
  [access.md](access.md).
- **Bridges.** The ACL on `/sdn/zones/localnetwork/vmbr0` covers the bridge
  named `vmbr0` on **every** node. Name the new node's guest bridge `vmbr0`
  and existing grants apply. Name it differently and they do not.

## 6. Bookkeeping

- Add the node to the table in [lab.md](lab.md).
- Once the hardening runbook is in place, rerun
  [`preflight.sh`](../blue3-deploy/preflight.sh). `ALLOW_FROM` must list every
  node, or the UI breaks between nodes.
- Remote commands: prefix them with `LC_ALL=C`. The workstation forwards
  `pt_BR` locale variables, and a node without that locale floods every
  command with perl warnings.
