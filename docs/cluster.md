# Cluster `blue3-lab` — topology and quorum

**As of:** 2026-09-25 · Every node runs `pve-manager 9.2.20+blue3.1` on hold

The plan is one cluster that holds every physical host, managed from a single
UI. b3pve1 and b3pve2 stay in it as UI entry points.

---

## Members

| Node | IP | What it is | Votes |
|---|---|---|---|
| b3p1 | 100.64.65.160 | physical host | 3 |
| spx1 | 100.64.65.202 | physical host, production guests | 3 |
| b3pve1 | 100.64.100.254 | **VM 111 on spx1**, UI entry point | 1 |
| b3pve2 | 100.64.100.253 | **VM 112 on spx1** | 1 |

Expected votes: 8, quorum: 5. HA is not configured, so losing quorum never
fences or reboots anything: `/etc/pve` becomes read-only and guests keep
running.

## Votes: physical host = 3, entry-point VM = 1

b3pve1 and b3pve2 are guests of spx1, so their votes always fail together with
spx1. With 1 vote per node, 3 of the 4 votes would live on one box. After a
reboot of spx1, only spx1 and b3p1 would be up: 2 of 4, no quorum. Without
quorum PVE does not autostart guests, so spx1's production guests would stay
down. The two entry-point VMs would stay down too, and they are exactly the
votes that would bring quorum back. That is a deadlock, broken only by hand
with `pvecm expected`.

With 3 votes per physical host:

| Situation | Votes up | Quorate (≥ 5)? |
|---|---|---|
| everything up | 8 | yes |
| spx1 reboots, b3p1 up | 3 + 3 = 6 once spx1 is back | yes: spx1's guests autostart |
| b3p1 down | spx1 3 + entry VMs 2 = 5 | yes |
| spx1 down | b3p1 3 | no. b3p1's guests keep running but cannot be managed |
| b3p1 down **and** spx1 reboots | spx1 3 | no. Needs `pvecm expected 3` on spx1 |

The last two rows are the limit of having two physical hosts. A third physical
host, or a QDevice on an independent machine, removes them. With 3 physical
hosts at 3 votes each (11 total, quorum 6), any single host can fail.

**Rule for new members:** a physical host joins with `--votes 3`. A VM that is
only a UI entry point keeps 1. See [new-node.md](new-node.md).

**Do not roll back VM snapshots of b3pve1 or b3pve2** while they are cluster
members. A node restored to an old state rejoins with a stale cluster
database.

## Known issue: the router NATs traffic addressed to spx1

**Found 2026-09-25, not fixed yet.**

**Symptom.** After spx1 joined, `corosync-cfgtool -s` showed spx1 ↔ b3p1
*connected*, but spx1 ↔ b3pve1 and spx1 ↔ b3pve2 *disconnected*. Totem could
not form a full ring, so the membership re-formed every 4 s: 44 times in
3 minutes. Restarting corosync did not help.

**Cause.** A capture on spx1 (`tcpdump -ni nic4 udp port 5405`) showed
packets from b3pve1 and b3pve2 arriving with the router's **public** address
as their source, instead of 100.64.100.254/253. The same packets reach b3p1
with their real source address. Only the source port changes there, which
knet tolerates. So a source-NAT rule on the gateway (100.64.65.1) matches
traffic *to spx1* specifically, typically a hairpin-NAT rule that belongs to a
port forward. Evidently knet does not bring a link up from an address that is
not a cluster node: the one path whose source address is rewritten is the only
one that stays disconnected. There is no filtering. ICMP and UDP on other
ports pass both ways.

**Current workaround.** corosync is **stopped** on b3pve1 and b3pve2. The
cluster runs on b3p1 + spx1 (6 of 8, quorate, stable). The two entry-point VMs
are out of the membership, so their UI shows a stale, read-only view. **Use
`100.64.65.160` or `100.64.65.202` meanwhile.** Both run the fork and the
80/443 redirect.

**Fix, on the router.** Exempt internal-to-internal traffic from source NAT,
with an `accept` rule placed **before** the NAT rule that matches, then drop
the existing connection-tracking entries for UDP 5405. The gateway's MAC
prefix looks like MikroTik. If it is, something like this (check the first
command's output before adding anything):

```
/ip firewall nat print where chain=srcnat
/ip firewall nat add chain=srcnat src-address=100.64.100.0/24 dst-address=100.64.65.0/24 action=accept place-before=0 comment="no NAT between internal nets"
/ip firewall nat add chain=srcnat src-address=100.64.65.0/24 dst-address=100.64.100.0/24 action=accept place-before=0 comment="no NAT between internal nets"
/ip firewall connection remove [find where protocol=udp and (dst-address~":5405" or src-address~":5405")]
```

**Then, on the nodes:**

```bash
ssh root@100.64.100.254 systemctl start corosync
ssh root@100.64.100.253 systemctl start corosync
ssh root@100.64.65.202 'corosync-cfgtool -s'        # nodes 1, 2, 3: connected
ssh root@100.64.65.160 'pvecm status | grep -E "Total votes|Quorate"'   # 8, Yes
```

If spx1 still shows nodes 1 and 2 as disconnected after about 30 s, stop
corosync on the two VMs again. That brings back the stable 6-of-8 state.

**Check it on every new host.** After a join, `corosync-cfgtool -s` on
**each** node must show every other node *connected*. A single one-sided link
is enough to make the membership churn.
