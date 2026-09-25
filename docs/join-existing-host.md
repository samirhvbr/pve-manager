# Joining a host that already runs guests

**Done once:** spx1, 2026-09-25. It had 16 guests (11 running), and it joined
without a reboot or a guest restart: the guest PIDs were identical before and
after.

This is the hard case of [new-node.md](new-node.md), step 2. A fresh host
needs none of it.

---

## What `pvecm add` does to a host with guests

- It **refuses** ("this host already contains virtual guests") unless you pass
  `--force`.
- With `--force`, it **deletes the host's cluster database**
  (`/var/lib/pve-cluster/config.db`, with a backup in
  `/var/lib/pve-cluster/backup/`) and takes the cluster's instead. Everything
  in `/etc/pve` is replaced: guest configs, `storage.cfg`, users, tokens,
  passwords, 2FA, `ceph.conf`, node certificates, and the root
  `authorized_keys`.
- **Running guests are not touched.** They are plain processes, so they keep
  running without their configs. They reappear once the configs are copied
  back.

## Before

1. **Back up `/etc/pve` and the rest**, into a directory outside `/etc/pve`:

   ```bash
   B=/root/blue3-prejoin-$(date +%Y%m%d-%H%M%S); mkdir -p $B
   cp -a /etc/pve/. $B/etc-pve/
   cp -a /var/lib/pve-cluster/config.db /etc/ceph /root/.ssh /etc/hosts /etc/network/interfaces $B/
   ps -eo pid,args | grep -E '[k]vm -id|[l]xc-start' | awk '{print $1}' | sort > $B/guest-pids-prejoin.txt
   ```

2. **Clear VMID conflicts.** VMIDs are unique across the cluster. Compare
   `qm list` / `pct list` on the host with `/cluster/resources`. Renumber one
   side with [`renumber-vms.sh`](../blue3-deploy/cluster/renumber-vms.sh).
   A running VM goes down for well under a minute. **Move the ACLs** on
   `/vms/<old>` as well. Otherwise, once the host joins, they grant access to
   *its* VM with that ID.

3. **Decide what not to migrate.** Users and ACLs from the host replace
   nothing: they are simply gone after the join. A local `Administrator` on
   `/` would become admin of the **whole cluster** if copied back as it is.

4. **Remove a Ceph that holds nothing** (0 OSDs, 0 pools) with
   `pveceph purge`, after backing up `/var/lib/ceph`. If the monitor is
   stopped first, purge cannot query it and leaves `ceph.conf` and a keyring
   behind. Delete those by hand.

5. **Let the host SSH to the join target.** Append the host's
   `/root/.ssh/id_rsa.pub` to the cluster's `/etc/pve/priv/authorized_keys`,
   then run `ssh root@<target> hostname` once from the host.

6. **Have a way in that does not depend on `/etc/pve`.** Keep console, IPMI or
   a root password ready. On PVE, `/root/.ssh/authorized_keys` is a symlink
   into `/etc/pve`. Between the database wipe and the first sync, **every SSH
   key is gone**. If the host cannot reach quorum, it stays like that.

## The join

Run it detached, so that a dropped SSH session cannot interrupt it, and chain
the restore right after it:

```bash
setsid nohup bash -c 'pvecm add 100.64.65.160 --use_ssh 1 --votes 3 --force 1; bash /root/restore.sh' \
    > /root/blue3-join.log 2>&1 < /dev/null &
```

`--votes 3` follows the rule in [cluster.md](cluster.md). The target is a
physical member, never a VM that runs on the joining host.

## Restore

In this order, only once `pvecm status` shows `Quorate: Yes` on the host:

1. **Storages**, each restricted to the host with `--nodes <host>`. This is
   mandatory for LVM: spx1's `local-lvm` is `pve/data`, and b3p1 has a VG
   with the **same name**. Without the restriction, b3p1 would see a second
   storage ID aliasing its own `b3p1-hdd` thin pool.

   ```bash
   pvesm add lvmthin local-lvm --vgname pve --thinpool data --content images,rootdir --nodes spx1
   pvesm add dir ssd --path /mnt/pve/ssd --content backup,snippets,iso,images,vztmpl,rootdir --is_mountpoint 1 --nodes spx1
   ```

2. **Guest configs.** Copy `$B/etc-pve/nodes/<host>/{qemu-server,lxc}/*.conf`
   into `/etc/pve/nodes/<host>/`. Skip any VMID that
   `/etc/pve/.vmlist` already has.

3. **API tokens, with their original secret.** `pveum user token add` creates
   a new secret, which breaks whatever uses the token. Create the token, then
   replace its line in `/etc/pve/priv/token.cfg` with the one from
   `$B/etc-pve/priv/token.cfg`, without printing it.

4. **Groups**, with `pveum group add`.

5. **The node certificate.** On spx1 the join failed to generate it
   ("Could not open ... pve-ssl.key"), and the node was left without
   `pve-ssl.pem`. Fix:

   ```bash
   pvecm updatecerts --force && systemctl reload-or-restart pvedaemon pveproxy spiceproxy
   ```

   The fingerprint changes. Clients that pin it (API integrations, PBS) need
   the new one.

## Check

```bash
ps -eo pid,args | grep -E '[k]vm -id|[l]xc-start' | awk '{print $1}' | sort | diff - $B/guest-pids-prejoin.txt && echo "no guest restarted"
corosync-cfgtool -s        # on EVERY node: every other node connected
pvesm status               # the host's storages active
```

Then continue with [new-node.md](new-node.md): step 3 (fork + hold) and
step 4 (web redirect).

## What went wrong on spx1, and why

- **The host could not reach two of the members**, and waited for quorum with
  an empty `/etc/pve` and no working SSH key. The router source-NATs traffic
  to spx1 (see [cluster.md](cluster.md)). Stopping corosync on the two
  unreachable members let spx1 and b3p1 form quorum on their own (6 of 8).
  The join then finished by itself, restore included. The two VMs were
  removed from the cluster the same day ([cluster.md](cluster.md), *History*).
- **The certificate was not generated**, and `pvecm updatecerts --force`
  fixed it.
