# Moving guests from a standalone host into the cluster

**Written:** 2026-10-27 · **Source:** a standalone PVE 7.4 host with 35 guests
· **Target:** b3p1

In October 2026, the guests of a standalone PVE 7.4 host started moving into
the cluster. Two methods were tried. This page records what each one does,
what broke, and the checks that a copy needs before it is started.

The guest list, the VMID map and each guest's state are kept **outside this
repo**, because the repo is public and that list ties VMIDs to customers.

---

## Method A: `qm remote-migrate` (tested, not used for the bulk)

It works from PVE 7.4 to 9.2, even though 7.4 marks it experimental. One VM of
100 GiB, migrated offline, took about 30 minutes. The MAC is kept, and the
guest lands on the node whose address is in the endpoint.

```bash
# on the source host, with the VM shut down
qm remote-migrate <vmid> <new-vmid> \
  'apitoken=PVEAPIToken=<user>@pve!<token>=<secret>,host=<node-ip>,fingerprint=<sha256>' \
  --target-bridge vmbr0 --target-storage b3p1-ssd
```

What to know:

- **The token needs `Sys.Incoming`** on the target, which `PVEVMAdmin` does
  not include. Create a temporary user, role and token for the move, and revoke
  them afterwards.
- **It refuses a VM with snapshots** ("remote migration with snapshots not
  supported yet"). It also complains about ISOs that a snapshot references.
  Delete the snapshot first, or use method B.
- **The source stays with `lock: migrate`.** That blocks `qm set`, including
  `onboot`, until `qm unlock <vmid>`.
- `<new-vmid>` renumbers during the copy. Without it, run
  [`renumber-vms.sh`](../blue3-deploy/cluster/renumber-vms.sh) afterwards.
- In a command sent over SSH, `pgrep -f <pattern>` matches the remote shell
  that runs it, so a "wait until the VM is down" loop never ends. That
  mistake added about half an hour of downtime to a production VM. Use
  `qm status`, or `pgrep -x`.

## Method B: backup to a PBS, then restore (used for the bulk)

A Proxmox Backup Server is defined as a storage on both sides. Each guest is
backed up on the source and restored on b3p1:

```bash
qmrestore <pbs-storage>:backup/vm/<vmid>/<time> <new-vmid> --storage b3p1-ssd
pct restore <new-vmid> <pbs-storage>:backup/ct/<vmid>/<time> --storage b3p1-ssd
```

- The source keeps running during the backup. Anything that changes after it
  is lost unless a final backup is taken at cut-over, with the original
  stopped.
- The MAC is kept unless you pass `--unique`. So **never start a copy while
  its original runs**: duplicate MAC and IP.
- No snapshot problem, because a backup carries the current state only.
- Adding the PBS storage needs `Datastore.Allocate` on `/storage`
  ([access.md](access.md)).

### One restore at a time per thin pool

On 2026-10-21, three restores ran in parallel into `b3p1-ssd`. b3p1 went grey
("unknown") in the UI for about 25 minutes, while its guests kept running.
`pvesm status` timed out at 60 s.

What happened, in order:

1. I/O pressure stayed at 20–38 %. udev took too long on the new device-mapper
   device of the third restore, and killed its worker.
2. The `lvcreate` of that restore kept waiting on the udev cookie that the dead
   worker would never complete (`do_semtimedop`).
3. The restore task was interrupted. The `lvcreate` was orphaned (parent PID
   1) while still holding the volume group lock `/run/lock/lvm/V_b3p1-ssd`.
4. Every `vgs`/`lvs` call queued behind it. pvestatd runs them every 10 s, so
   the node's status stopped updating. **It does not heal by itself.**

Diagnose:

```bash
lslocks | grep lvm                                          # who holds the VG lock
ps -eo pid,ppid,stat,wchan:20,args | grep '[l]vcreate'      # ppid 1, sleeping
journalctl -u systemd-udevd | grep 'taking a long time'
dmsetup udevcookies                                         # the pending cookie
```

Fix:

```bash
dmsetup udevcomplete <cookie>      # the lvcreate exits by itself within seconds
```

`kill` does nothing: while it waits, `lvcreate` blocks every signal except
SIGKILL (see `SigBlk` in `/proc/<pid>/status`). After the fix, remove what the
broken restore left behind: a stub config (`memory: 128`) and a volume. **`lvs`
did not list that volume, but `pvesm list <storage>` did.** Use
`qm destroy <id>`.

Restore one guest at a time per thin pool, or pass `--bwlimit`.

## VMIDs

The source's IDs collide with the cluster's. The rule since 2026-10-27:

- **source ID + 1000** when that ID is free in the cluster;
- otherwise, the next free ID from 1140 up. The copies made on 21–22/10
  already use 1120–1139 sequentially, and they keep those IDs.

Check `/cluster/resources` before restoring, and the ACLs too. An ACL on
`/vms/<id>` applies to whatever guest gets that ID later. For example,
`/vms/115`, `/vms/116` and `/vms/118` belong to a lab account.

## Networks

The source has `vmbr0` (its LAN, untagged, plus tagged VLANs) and `vmbr1` (a
"Telefonia" bridge on a port with no link). The cluster has the same two
names. See [cluster.md](cluster.md), *Bridges*.

**A guest's network is not there until a capture shows it.** On 2026-10-16,
the source LAN was said to be trunked to the cluster, but it did not reach
`nic4` on either node. Before you start a copy, watch for 30 s on the target
node:

```bash
timeout 30 tcpdump -nnei nic4 -c 5 'arp and net <guest-lan>'   # untagged LAN
timeout 30 tcpdump -nnei nic4 -c 5 'vlan <tag>'                 # each VLAN the guest uses
```

Copies are restored with `link_down=1` on every NIC whose network is not
validated yet.

Get the guest's **real** IP before you test it: from ARP, the guest agent or
the guest itself. The description field was wrong for at least one VM.

## Before starting a copy

- [ ] Every `bridge=` in its config exists on the node:
      `ls /sys/class/net/<bridge>`.
- [ ] Every volume exists: `qm showcmd <id> >/dev/null` fails on a missing
      one. Two copies referenced an installer ISO that is not in the cluster.
      Eject it with `qm set <id> --ide2 none,media=cdrom`.
- [ ] The original is stopped, and set to `onboot: 0` on the source.
- [ ] `onboot` on the copy is what you want. A copy with `onboot: 1` starts at
      the node's next reboot, with the original's MAC.
- [ ] A guest with `cpu: host` moves offline only.
- [ ] Its networks passed the capture above, or the NICs stay `link_down=1`.
