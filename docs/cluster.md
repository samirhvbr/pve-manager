# Cluster `blue3-lab` — topology and quorum

**As of:** 2026-11-17 · All four nodes run `pve-manager 9.2.26+blue3.1` on
hold. b3p1 and spx1 boot kernel 7.0.14-28; pr9 and sgpu1, which joined that
day, boot 7.0.14-29.

One cluster that holds every physical host. **Any member serves the UI for the
whole cluster.** There is no dedicated entry-point node. Use
`100.64.65.160` or `100.64.65.202` (bare IP works, thanks to the 80/443
redirect, installed on all four).

The name `blue3-lab` is left over from when the cluster was only the lab.
Renaming it means editing `cluster_name` and restarting corosync on every
node. That is deferred.

---

## Members

| Node | IP | What it is | Votes |
|---|---|---|---|
| b3p1 | 100.64.65.160 | physical host | 3 |
| spx1 | 100.64.65.202 | physical host, production guests | 3 |
| pr9 | 100.64.65.112 | physical host (Dell R720), no guests yet; joined 2026-11-17 | 3 |
| sgpu1 | 100.64.65.111 | physical host (Dell R720) with a GPU passed through to one VM; joined 2026-11-17 | 3 |

Expected votes: 12, quorum: 7. HA is not configured, so losing quorum never
fences or reboots anything: `/etc/pve` becomes read-only and guests keep
running.

How the two new hosts joined: [new-node.md](new-node.md) for pr9 (fresh
install) and [join-existing-host.md](join-existing-host.md) for sgpu1 (one VM,
renamed before the join).

## Votes: 3 per physical host

The rule is **every physical host joins with `--votes 3`**
([new-node.md](new-node.md)). With only physical members, 3 each behaves
exactly like 1 each. The rule exists so that the numbers stay right if a
non-host member is ever added again. That was the case until 2026-09-25, see
below.

With four hosts, any one of them can be down:

| Situation | Votes up | Quorate (≥ 7)? |
|---|---|---|
| all four up | 12 | yes |
| one host down or rebooting | 9 | yes. The others keep full management |
| two hosts down | 6 | no. The remaining hosts' guests keep running but cannot be managed |

Until 2026-11-17 the cluster had only b3p1 and spx1 (6 votes, quorum 4), so a
reboot of either host left the other without quorum. *Rebooting a host* below
was written in that period. With four hosts, rebooting one no longer costs
quorum.

## Rebooting a host

Done on both hosts on 2026-11-07 for a kernel update. One host at a time.

- **Autostart follows `onboot`, so set it first.** The rule is: a running guest
  has `onboot: 1`, a stopped guest has `onboot: 0`, and benchmark VMs have
  `onboot: 0` whatever their state, because they run only during a test.
  Before that date, 16 running guests had no `onboot` and would have stayed
  off, and 7 stopped ones would have started.
- **A snapshot rollback restores `onboot`.** The benchmark VMs' snapshots were
  taken with `onboot: 1`, so each rollback by the benchmark driver turns
  autostart back on. Set `onboot: 0` again right before the reboot, and do
  not reboot while a benchmark VM is running.
- **While one host is down, the other is not quorate.** Its guests keep
  running, but nothing can be started, stopped or changed there. That also
  breaks any API client working against it, such as the benchmark driver.
- **After the reboot,** compare guest by guest with the state saved before:
  the same guests running, the same ones stopped. Pending configuration
  changes are applied at that boot, and guests come back on the newly
  installed QEMU.
- **Guest shutdown:** most VMs have no guest agent. They get an ACPI shutdown,
  and one that ignores it is stopped hard after the timeout.
- **Time:** the host was out of the cluster for 14 min on spx1 and 7 min on
  b3p1, most of it in the Dell POST.

## Bridges

b3p1 and spx1 have the same two bridges, with the same names, so a guest's
config works on either node and ACLs on `/sdn/zones/localnetwork/<bridge>`
cover both.

pr9 and sgpu1 (since 2026-11-17) separate the three roles on three ports. Their
two 10G ports are legs of one QSFP-to-4×SFP+ breakout cable on switch port
`Eth1/9` of `SW01-Servidores`, and the switch names them in LLDP:

| Role | pr9 | sgpu1 | Switch side |
|---|---|---|---|
| management and corosync | `nic0` (1G copper), IP on the port itself, **no bridge** | `nic0`, same | access, management network |
| guests: `vmbr0` | `nic6` | `nic4` | `ServerPort02/Trunk02` / `Trunk01`: tagged guest VLANs (1001, 50, 59, 1002, 1021, 1051) |
| backups: VLAN 1098 | `nic7.1098`, `100.64.98.112/24` | `enp68s0f1.1098`, `100.64.98.111/24` | `ServerPort02/Backup02` / `Backup01`: 1098 **tagged** |

- **The copper port has no bridge,** so the UI never offers it to a guest.
- **Guest NICs on these nodes always carry a tag.** pr9's trunk also carries
  untagged traffic from other networks.
- **Backup traffic stays off the router.** VLAN 1098 has no gateway on the
  hosts, so traffic to the PBS (`100.64.98.2`) leaves through that port.
  b3p1 and spx1 still reach the PBS through the router.
- **A tagged guest started before `vmbr0` moved keeps its old VLAN bridge.**
  PVE created `vmbr0v<tag>` on the old port and does not rebuild it on
  `ifreload`. Stop the guest, delete `vmbr0v<tag>` and `<oldport>.<tag>`, then
  start it again.
- Applied with a script that arms a 4-minute rollback before `ifreload`. The
  rollback is cancelled only after these checks pass: gateway, PBS on 8007
  through the 1098 port, corosync links, and 12 votes.

| Bridge | Port | Kind | What it carries |
|---|---|---|---|
| `vmbr0` | `nic4` (10G) | plain; tagged NICs get `vmbr0v<tag>` | management, corosync, and the guests' LAN and VLANs |
| `vmbr1` | `nic5`, the 10G card's second port, with no SFP and no link | plain, comment `Telefonia` | nothing beyond the node |

`vmbr1` mirrors the bridge of the same name on the standalone host that guests
are migrating from ([guest-migration.md](guest-migration.md)). That bridge's
port has no link either. Guests in the same VLAN on `vmbr1` reach each other
**on the same node**. Copies on different nodes do not see each other, and
nothing leaves the node.

- **If someone cables `nic5`, every guest on `vmbr1` ends up on that wire**,
  including router copies with one NIC per VLAN. Check `vmbr1`'s guests before
  plugging anything into that port.
- It needs a port. On a plain bridge, PVE creates one sub-bridge per VLAN tag
  on the bridge's physical port (`vmbr1v33` on `nic5.33`). With no port, it
  refuses a tagged NIC with "no physical interface on bridge". The first
  version, created on 2026-10-23, was port-less and VLAN-aware for that
  reason. On 2026-10-27 it was rebuilt on `nic5`, to match the source host.
- New node: [`blue3-deploy/network/vmbr1.sh`](../blue3-deploy/network/vmbr1.sh).
  It touches `vmbr1` only (`ifup vmbr1`, never `ifreload -a`), so `vmbr0`, and
  corosync with it, are never reloaded.

**Pending changes in the UI.** `/etc/network/interfaces.new` holds a network
change made in the UI that was not applied. While that file exists, *Network*
shows "Pending changes". *Apply Configuration* then installs that file as a
whole, and any edit made to `interfaces` in the meantime is lost. *Revert*
deletes the file. spx1 had one from 2026-09-21 (it only reordered lines) until
it was reverted on 2026-10-27. Check for it before editing `interfaces` by
hand.

## Templates: one copy per host

The `blue3-debian` template lives on local storage, and PVE cannot clone a
template on local storage to another host. VMIDs are cluster-wide, so every
host has its own copy under its own ID:

| VMID | Host | Storage |
|---|---|---|
| 200 | b3p1 | `b3p1-hdd` (the original) |
| 9201 | spx1 | `local-lvm` (RAID 1 of SSDs; spx1's `ssd` and `exthd` arrays were degraded) |
| 9202 | pr9 | `pr9-ssd` |
| 9203 | sgpu1 | `local-lvm` |

The copies were made on 2026-11-17 from 200:

1. One full clone of 200 into `b3p1-ssd`, reading `b3p1-hdd` at no more than
   150 MiB/s (`--bwlimit 153600`), because that disk is shared with running
   guests. The CD drive was emptied, since 200 points at an ISO only b3p1 has.
2. Two more full clones from that copy, SSD to SSD.
3. For each copy, an offline
   `qm migrate <id> <host> --targetstorage <storage> --migration_network 100.64.65.0/24`
   (60 GB over the 1G management link: about 5 minutes to spx1, 9 to pr9 and
   sgpu1), then `qm template <id>` on the host.

The copies are independent. A change made to 200 does not reach them; to
change `blue3-debian`, change 200 and make the copies again.

Like 200, the copies have `net0` on `vmbr0` with no VLAN tag. On pr9 and sgpu1,
`vmbr0` is on the 10G trunk port, where an untagged NIC lands on the trunk's
native VLAN, so give each clone its VLAN tag.

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
- **Seen again on 2026-10-20, on b3p1.** Browsers on the internal office
  network (10.100.100.0/22) reach b3p1 from the router's *public* addresses,
  according to `pvedaemon`'s auth log. That matters for the hardening runbook:
  `ALLOW_FROM` (step 7) and fail2ban (step 8) only ever see the router.
  Allow-listing that address admits everyone behind the NAT, and banning it
  locks everyone out. Fix the srcnat before those two steps.

Because every member serves the whole cluster's UI anyway, they were removed
instead: separated to standalone (corosync config deleted, corosync disabled,
other nodes' directories removed), then `pvecm delnode` on b3p1, then their
directories and root SSH keys were removed on both sides.

**Check links on every new host.** After a join, `corosync-cfgtool -s` on
**each** node must show every other node *connected*. A single one-sided link
is enough to make the membership churn.
