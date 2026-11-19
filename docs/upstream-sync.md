# Following upstream without losing the fork

**First done:** 2026-09-24 · 9.2.10+blue3.1 → 9.2.20+blue3.1  
**Last done:** 2026-11-19 · 9.2.26+blue3.1 → 9.2.31+blue3.1

---

## What happened

On 2026-09-21 at 12:03, an `apt upgrade` on b3pve1 and b3pve2 replaced
`pve-manager 9.2.10+blue3.1` with the stock `9.2.20`. The UI went back to
Proxmox branding on both nodes. Nothing else from the fork is packaged, so
nothing else was lost.

That is the version scheme working as designed, not a bug:

```bash
dpkg --compare-versions "9.2.10+blue3.1" lt 9.2.20 && echo "apt sees 9.2.20 as newer"
```

`<upstream>+blue3.<N>` exists so that apt keeps seeing Proxmox releases,
security fixes included (see [CLAUDE.md](../CLAUDE.md), *Versionamento*). But
apt does more than *see* the newer version. With nothing holding the package,
it installs it.

## The hold

Every node running the fork has `pve-manager` on hold:

```bash
apt-mark hold pve-manager
apt-mark showhold            # should list pve-manager
```

With the hold, a new upstream `pve-manager` is still visible. It shows up in
`apt list --upgradable` and in the node's *Updates* panel, and `apt upgrade`
reports it as *kept back*. The only change is that the fork no longer reverts
silently. So both properties of the version scheme still hold: our build beats
the official one, and we still see when upstream moves.

**Trade-off:** an upstream security fix in `pve-manager` waits until we merge
it. That cost comes with running a fork at all. The hold turns an unnoticed
revert into a visible pending update.

`proxmox-ve` may start being kept back too, once it depends on a newer
`pve-manager`. That is expected, and it means the same thing: sync the fork.

## Procedure when upstream moves

### 1. Find the upstream commit

A stock `pve-manager` reports its git commit in `pveversion`:

```
pve-manager/9.2.20/49318c671b82f31e
```

That hash is upstream's `bump version to X` commit. Without a stock node to
read it from, find the bump commit in `git log upstream/master`.

### 2. Merge it into a branch

```bash
git remote add upstream https://git.proxmox.com/git/pve-manager.git   # once per clone
git fetch upstream
git switch -c upstream-X
git merge --no-ff <bump-commit>
```

**Merge, don't rebase.** A rebase rewrites `master` and needs a force-push.
A merge produces the same tree without that.

### 3. Resolve `debian/changelog`

This file always conflicts: both sides add an entry at the top. Take
upstream's file, put the new fork entry `X+blue3.1` on top, and leave the
older fork entries where their versions sort. For example, `9.2.10+blue3.1`
sits between `9.2.11` and `9.2.10`, so the file stays in descending version
order:

```bash
dpkg-parsechangelog -S Version     # must print X+blue3.1
```

### 4. Check for new places to rebrand

Upstream can add new subscription notices or Proxmox strings:

```bash
grep -rn "checked_command" www/manager6        # only node/Subscription.js may call it
git diff <old-bump> <new-bump> -- www/ | grep -E '^\+' \
    | grep -iE 'proxmox virtual|proxmox\.com|subscription|checked_command'
```

The 9.2.10 → 9.2.20 and 9.2.20 → 9.2.26 syncs found none.

### 5. Bump and record

- `version.md` → `X+blue3.1` (`N` resets to 1 on a new upstream)
- a new entry at the top of `CHANGELOG.md`

### 6. Build on a lab node, as a non-root user

The build VM is `b3pve1`, a standalone PVE with no guests. **Bring its
packages to the target release first.** The new `Build-Depends` ask for the
libraries released with the new upstream, and those can `Break` the old fork
installed on the build VM. In the 9.2.31 sync, `libpve-storage-perl` 9.1.18
broke `pve-manager << 9.2.29`. The build VM therefore took stock 9.2.31 for
the build, then the freshly built fork as its first install.

```bash
su - samir -c 'cd ~/build-X/pve-manager && make check && make deb'
```

**Do not build as root.** Since 9.2.1x, `test/CephKeyMigrationScript_test.pl`
expects `bin/pve-cephx-rotate-service-keys` to fail with *must run as root*.
As root, that check passes, and two tests fail (375 and 376). `make deb` runs
the same tests through `dh_auto_test`, so skipping `make check` does not help.

Get the tree onto the node with a bundle. That needs no credentials on the
node, and the Makefile's `git rev-parse` still has a `.git` to read:

```bash
git bundle create fork.bundle upstream-X
scp fork.bundle root@<node>:/home/samir/build-X/
```

The `.deb` is written to the checkout directory. The Makefile builds in a
subdirectory and writes to its parent.

### 7. Install on each node, one at a time

**Use IPv4 for apt.** The nodes have no IPv6 route, and on 2026-11-19 apt on
pr9 failed downloads on `download.proxmox.com`'s IPv6 address. Pass
`-o Acquire::ForceIPv4=true -o Acquire::Retries=3`.

**Every node needs to reach `download.proxmox.com`.** On 2026-11-19, b3p1 had
had no route to the internet since 2026-11-07: its traffic stopped at the
second hop, while spx1, behind the same gateway, passed. b3p1 stayed on
9.2.26+blue3.1 until that was fixed. A node can run one fork version behind
the others; the cluster works with mixed minor versions.

Install the fork in the **same apt transaction** as the packages the hold kept
back. With the old fork on hold, `apt full-upgrade` keeps back every package
whose new version `Breaks` the old `pve-manager`. In the 9.2.26 sync these were
9 packages, among them `pve-container` (`Breaks: pve-manager (<< 9.2.22)`) and
`libpve-rs-perl` (`<< 9.2.26`). The new fork depends on some of them. A plain
`dpkg -i` then leaves `pve-manager` unpacked but not configured, which happened
on spx1 on 2026-11-07.

```bash
apt full-upgrade                                  # pve-manager stays on hold
kept=$(apt list --upgradable 2>/dev/null | grep upgradable | cut -d/ -f1 | grep -vx pve-manager)
apt-mark unhold pve-manager
apt-get -s install ./pve-manager_X+blue3.1_all.deb $kept   # no "Remv", ends with "Conf pve-manager (X+blue3.1"
apt-get install ./pve-manager_X+blue3.1_all.deb $kept
apt-mark hold pve-manager
dpkg-query -W -f='${db:Status-Abbrev}\n' pve-manager     # "hi": held and installed
pveversion                          # pve-manager/X+blue3.1/<fork-commit>
curl -sk https://127.0.0.1:8006/ | grep -o '<title>[^<]*'   # "<node> - Blue3 Cloud"
```

If a node was already left with `pve-manager` unpacked (`hU`), run the same
`apt-get install` with the kept-back packages alone: it configures the fork.

The postinst reloads (or restarts) `pvedaemon`, `pvestatd`, `pveproxy`,
`spiceproxy` and `pvescheduler`. Guests keep running. Open UI sessions may have
to log in again. Do one node at a time, and confirm the cluster is
quorate before moving on.

### 8. Push

Once every node serves the fork, merge the branch into `master` and push.
