# Colleague access — one user, one pool

**First applied:** 2026-09-25 · **Verified:** end to end, logged in as the
colleague

How to give a colleague an account that creates and runs VMs without seeing or
touching anyone else's. This repository is public, so the accounts themselves
are not listed here. Run `pveum user list` and `pveum acl list` on any node.

The reasoning behind the model (pools, ACL paths, no quotas) is in
[multi-tenancy.md](multi-tenancy.md).

---

## The recipe

Realm `pve`, which lives in the cluster's user database. A `pam` user would
need a Linux account on every node.

```bash
U=login@pve; P=login                 # pool named after the person

pveum user add $U --firstname <First> --lastname <Last>
pveum pool add $P
pveum acl modify /pool/$P --users $U --roles PVEVMAdmin,PVEPoolUser
for s in b3p1-hdd b3p1-ssd b3p1-iso; do
    pveum acl modify /storage/$s --users $U --roles PVEDatastoreUser
done
pveum acl modify /sdn/zones/localnetwork/vmbr0 --users $U --roles PVESDNUser
pveum acl modify /vms/200       --users $U --roles PVETemplateUser   # clone blue3-debian
pveum acl modify /nodes/b3p1    --users $U --roles PVEAuditor        # see node load
```

| Path | Role | What it gives |
|---|---|---|
| `/pool/<P>` | `PVEVMAdmin` | Create, configure, start, console, snapshot, delete and convert to template, for VMs in the pool |
| `/pool/<P>` | `PVEPoolUser` | See the pool, so it can be chosen in the create wizard |
| `/storage/<id>` | `PVEDatastoreUser` | Create disks there, or use its ISOs |
| `/sdn/zones/localnetwork/vmbr0` | `PVESDNUser` | Attach NICs to `vmbr0` (on every node) with any VLAN tag, because the ACL propagates |
| `/vms/200` | `PVETemplateUser` | Clone the `blue3-debian` template (VMID 200 since 2026-09-25; it was 100) |
| `/nodes/b3p1` | `PVEAuditor` | Read-only node summary: free RAM and CPU for sizing |

**The pool is mandatory when creating.** `VM.Allocate` is granted on the pool,
so a VM created without `pool=<P>` is refused (403). Tell the colleague: in the
*General* tab, pick the pool.

## What the colleague cannot do

Tested through the API, logged in as the colleague. Each of these returned 403:

- read the config of a VM outside the pool, or stop it. Those VMs do not even
  appear in the resource tree.
- read a storage that was not granted (`b3p1-nvme`)
- read the status of a node other than `b3p1`
- create a VM without choosing the pool

Implied by the roles, but not tested: no host shell (no `Sys.Console`), and no
changes to cluster options, users or ACLs (no `Sys.Modify`, `User.Modify` or
`Permissions.Modify`).

`GET /cluster/options` does answer 200. That is by design: every user gets a
filtered subset of the datacenter options, which the UI needs for keyboard and
console defaults.

## What PVE cannot limit

**RAM and vCPU have no quota.** The colleague can size a VM up to the node's
entire RAM. Disk is bounded only by the size of the granted storages. Detail
and options: [multi-tenancy.md](multi-tenancy.md), section 4.

## Docker

- **In a VM:** nothing more to grant. This is the recommended path.
- **In an LXC container:** it needs `nesting=1`, which the colleague can set on
  unprivileged containers, and usually `keyctl=1`, which only `root@pam` can
  set (`PVE/LXC.pm`, `check_ct_modify_config_perm`). Containers also need a
  storage with `vztmpl` content for their templates, and none is granted today.

Other things that are not granted today, and what granting them takes:

| Need | Grant |
|---|---|
| Upload ISOs | `PVEDatastoreAdmin` on `/storage/b3p1-iso`, or just the `Datastore.AllocateTemplate` privilege |
| Back up VMs | `PVEDatastoreUser` on a storage with `backup` content |
| Custom cloud-init snippets | a storage with `snippets` content |

## Handing over the password

1. Generate it, and set it through stdin, so it never appears in a command
   line: `printf '%s\n%s\n' "$PW" "$PW" | ssh root@<node> pveum passwd <U>`.
   `pveum` reads stdin when it is not a terminal.
2. Write it into a file **outside this repository**, with mode 600. The repo is
   public, and the AUDITOR's reports are committed text that can transcribe a
   secret.
3. The colleague changes it on first login (user menu → *Password*), and
   enrolls TOTP (user menu → *TFA*).

## Named admins

Admins get their own `pve` account with `Administrator` on `/`. That role
applies to every node, including hosts that join later. `root@pam` stays as
break-glass, as in step 5 of the runbook
([blue3-deploy/README.md](../blue3-deploy/README.md)). Hand the password over
the same way as above.

When a host with local users joins the cluster, its users, ACLs and
passwords are dropped. See [join-existing-host.md](join-existing-host.md).
Recreate only the accounts you still want, and scope them on purpose.

## Revoking

Uncheck *Enabled* on the user, or run `pveum user modify <U> --enable 0`. It
takes effect on the next API call. See [multi-tenancy.md](multi-tenancy.md),
section 1, for the one caveat about open consoles.
