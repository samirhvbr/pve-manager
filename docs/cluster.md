# Cluster `blue3-lab` — topology and quorum

**As of:** 2026-09-25 · Every node runs `pve-manager 9.2.20+blue3.1` on hold

One cluster that holds every physical host. **Any member serves the UI for the
whole cluster.** There is no dedicated entry-point node. Use
`100.64.65.160` or `100.64.65.202` (bare IP works, thanks to the 80/443
redirect).

The name `blue3-lab` is left over from when the cluster was only the lab.
Renaming it means editing `cluster_name` and restarting corosync on every
node. That is deferred.

---

## Members

| Node | IP | What it is | Votes |
|---|---|---|---|
| b3p1 | 100.64.65.160 | physical host | 3 |
| spx1 | 100.64.65.202 | physical host, production guests | 3 |

Expected votes: 6, quorum: 4. HA is not configured, so losing quorum never
fences or reboots anything: `/etc/pve` becomes read-only and guests keep
running.

## Votes: 3 per physical host

The rule is **every physical host joins with `--votes 3`**
([new-node.md](new-node.md)). With only physical members, 3 each behaves
exactly like 1 each. The rule exists so that the numbers stay right if a
non-host member is ever added again. That was the case until 2026-09-25, see
below.

With two hosts, both must be up for quorum:

| Situation | Votes up | Quorate (≥ 4)? |
|---|---|---|
| both up | 6 | yes |
| one host reboots | 3, then 6 once it is back | yes after the reboot, and its guests autostart |
| one host down for a while | 3 | no. The other host's guests keep running but cannot be managed |
| one host down **and** the other reboots | 3 | no. Needs `pvecm expected 3` to autostart guests |

A third physical host (9 votes, quorum 5), or a QDevice on an independent
machine, lets any single host fail.

## History: the entry-point VMs (removed 2026-09-25)

b3pve1 (100.64.100.254) and b3pve2 (100.64.100.253) were the original lab
cluster. For a few hours they were members of this cluster as UI entry points.
They turned out to be **VMs 111 and 112 on spx1**, which caused two problems:

- **Correlated votes.** Three of four members lived on spx1. With equal
  votes, a reboot of spx1 would have left the cluster without quorum. Without
  quorum no guest autostarts, including the two VMs whose votes were needed:
  a deadlock. The 3-vote rule came from this.
- **Router source NAT.** The gateway (100.64.65.1) source-NATs traffic from
  the VLAN 1001 network *to spx1* to its public address. A capture on spx1
  showed the VMs' corosync packets arriving from that address, while b3p1
  received the same packets with their real address. knet never brought those
  links up, and the membership re-formed every 4 s. This is likely a
  hairpin-NAT rule that belongs to a port forward. The fix belongs on the
  router: exempt internal ↔ internal traffic from srcnat, with an `accept`
  rule placed before the NAT rule. It is **still worth doing**, because every
  service on spx1 sees VLAN 1001 clients as the public IP. But it no longer
  affects the cluster.

Because every member serves the whole cluster's UI anyway, they were removed
instead: separated to standalone (corosync config deleted, corosync disabled,
other nodes' directories removed), then `pvecm delnode` on b3p1, then their
directories and root SSH keys were removed on both sides.

**Check links on every new host.** After a join, `corosync-cfgtool -s` on
**each** node must show every other node *connected*. A single one-sided link
is enough to make the membership churn.
