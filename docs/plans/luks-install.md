# Fix plan — DevOS encrypted (LUKS) install

Status: planned (Phase 1). Branch: `fix/luks-install`. **No ISO rebuild in this branch.**

## Context

DevOS has **no working full-disk-encryption path** — not regressed, never wired end-to-end.
A source-level audit of the installer (GUI Calamares + CLI `install.sh`) plus the pinned
upstream Calamares **3.4.2** module sources found the stock encrypted chain is complete and
correct. There is exactly **one** gating breaker, plus a defense-in-depth hygiene item:

1. **(GATING) DevOS's hardcoded mkinitcpio HOOKS override defeats Calamares.** `initcpiocfg`
   correctly adds the `encrypt` hook for a LUKS root, but `devossetup` (and its `install.sh`
   mirror) write `/etc/mkinitcpio.conf.d/devos.conf` with a fixed `HOOKS=` that has no
   `encrypt`. A `conf.d` drop-in overrides the main config, so the encrypt hook is discarded →
   an encrypted root that can't be unlocked → unbootable. **This is the sole load-bearing fix
   (C2).**
2. **(HYGIENE, not gating) `cryptsetup` is implicit.** The C++ `partition` job shells out to
   the `cryptsetup` binary (`partition/jobs/FillGlobalStorageJob.cpp:70,133-134`;
   `ClearMountsJob.cpp:331`), and the target initramfs `encrypt` hook needs it. It is **not**
   an explicit line in `packages.x86_64` — **but the pre-rebuild live probe found it is already
   in the ISO**, pulled transitively (systemd's `libcryptsetup.so` dependency; `/usr/bin/cryptsetup`
   + `libcryptsetup.so.12` + the systemd cryptsetup token plugins are all in the built
   `airootfs.sfs`). So C1 (add it explicitly) is **not** the gating fix originally assumed —
   it just makes the dependency intentional rather than relying on systemd to keep pulling it.

> **Failure-mode correction:** because cryptsetup is already present, the partition module's
> "Encrypt system" checkbox is almost certainly **already enabled** on the current ISO. So a
> user can tick it, set a passphrase, install — and get a **silently unbootable** system (the
> encrypt hook is stripped). The original audit framed this as "encryption unavailable"; it is
> actually "encryption appears to work but is broken," which raises C2's user-impact severity.

Everything else in the stock chain is present and verified: `partition` seeds
`luksMapperName`/`luksUuid`; `mount` mounts the already-open mapper; `fstab` writes
`/etc/crypttab` + mapper fstab; `bootloader` writes `cryptdevice=UUID=<uuid>:<mapper>
root=/dev/mapper/<mapper>` for the udev `encrypt` hook (`bootloader/main.py:141,165-170`).

### Decision baseline (Phase 0)
- **D1 — single encrypted root.** Drop the hibernation-sized `suspend` swap choice; keep
  `none/small/file`. No `luksopenswaphookcfg`, no `resume` hook. (Hibernation is already
  non-functional: no resume hook, no default swap.)
- **D2 — CLI guard.** `install.sh` refuses LUKS targets; full CLI LUKS support is a follow-up.
- **D3 — converge GUI → CLI curated cmdline** via `bootloader.conf` `kernelParams` +
  `loaderEntries` (mechanism verified: `bootloader/main.py:136`, schema, `create_loader`).

---

## Pre-rebuild live probe — DONE (headless artifact check)

**Run + result (2026-06-10):** `unsquashfs -l` of the built `out/devos-2026.05.27-x86_64.iso`
→ `airootfs.sfs` shows **`/usr/bin/cryptsetup` + `/usr/lib/libcryptsetup.so.12`** already
present (transitive systemd dep; the `cryptsetup-token-systemd-*.so` plugins are there too).
`cryptsetup` is *not* an explicit line in `packages.x86_64`, yet ships anyway.

**Conclusion:** C1 is **not** gating — cryptsetup is already in the ISO. The "Encrypt system"
checkbox is therefore almost certainly **already enabled** on the current ISO, so step 2 below
(`pacman -Sy cryptsetup`) would be a **no-op**. The live GUI probe no longer tests C1; the
decisive empirical test moves to **T2 on the FIXED ISO** (does the encrypted install now boot —
i.e. did C2 put the `encrypt` hook into the GUI-built initramfs).

Optional GUI confirmation (maintainer, at a display) on the **current** ISO — expect the
checkbox already enabled, no `pacman` needed:

1. Boot `out/devos-2026.05.27-x86_64.iso` under UEFI (OVMF) to the live session.
2. Launch Calamares → Partitions → "Erase disk" → confirm **"Encrypt system" is already enabled**
   and accepts a passphrase, then cancel. (If unexpectedly greyed → escalate: kpmcore/calamares
   LUKS support, re-check the PKGBUILD skip-list.)

---

## Changes (one commit each; smallest-first)

> All paths are in the `devos/` repo. **C2 is the load-bearing fix**; C1 is hygiene (cryptsetup
> is already in the squashfs transitively — see the probe above). Each change is independently
> safe.

### C1 — Declare `cryptsetup` explicitly · `packages.x86_64` · ISO rebuild
Already present transitively (systemd); this makes the dependency intentional so encryption
doesn't silently break if systemd ever stops pulling it. **Not the gating fix.** `lvm2` not
added (plain ext4-on-LUKS). **Risk:** none functional — additive/no-op (package already
installed); SEC-04 clean (official core package), DEVOS-04 not a MusicOS pattern.

### C2 — Add the `encrypt` hook · `devossetup/main.py` (`INSTALLED_HOOKS`) + `installer/install.sh` (HOOKS line) · ISO rebuild
Insert `encrypt` after `block`, before `filesystems`. Ordering verified safe (plymouth,
keyboard, block precede encrypt). **No-op on unencrypted installs** (the hook does nothing
without `cryptdevice=`). Both files are the canonical keep-in-sync pair.
**Risk:** low. If `cryptsetup` is somehow absent at build, `mkinitcpio` with the `encrypt` hook
warns but still builds; with C1 in place this can't happen. Unencrypted installs are unaffected.

### C3 — GUI cmdline + loader parity · `airootfs/etc/calamares/modules/bootloader.conf` · ISO rebuild
Add `kernelParams: ["quiet","loglevel=3","vt.global_cursor_default=0"]` (the module
auto-appends `splash` — plymouth present — `rw`, and `root=`/`cryptdevice=`) and
`loaderEntries: ["timeout 3","console-mode max","editor no"]` (otherwise the GUI `loader.conf`
has no timeout → no menu / unreachable fallback).
**Risk:** low. Cosmetic/UX + recoverability; both keys are schema-validated. Verify the GUI
cmdline in T1.

### C4 — CLI LUKS guard · `installer/install.sh` (after the mountpoint checks) · runtime-testable
Refuse a `/dev/mapper/*` root with a clear message (the CLI loader entry only writes
`root=PARTUUID=`, which is wrong for a mapper root). **Risk:** low; quoted `findmnt`, pattern
match only (SEC-03 clean). Does not affect unencrypted CLI installs.

### C5 — Drop hibernation swap option · `airootfs/etc/calamares/modules/partition.conf` · ISO rebuild
Remove `suspend` from `userSwapChoices` (keep `none/small/file`). Hibernation is unwired (no
`resume` hook) and a LUKS foot-gun. **Risk:** low; removes a broken UI option only. Ordinary
swap (`small`/`file`) unaffected.

### C6 — CLI loader timeout · `installer/loader/loader.conf`
**Already satisfied on `master`** (`timeout 3`, `console-mode max`, `editor no` present). No
change needed on this base; recorded for completeness. (The `timeout 0` seen during the audit
was uncommitted WIP, not master.)

## Explicitly deferred (not in this branch)
- TRIM / `allow-discards` (Calamares 3.4.2 emits none; injecting needs a cmdline rewrite; also a
  security/perf trade-off).
- Full CLI LUKS support (D2 follow-up); encrypted swap + hibernation (D1 alternative).
- Boot-entry MODEL unification (GUI uses `kernel-install`/BLS, CLI hand-writes static entries).
- Peripheral install-blockers (separate PR): `welcome.conf` `internet` mandatory→required; the
  dead Rofi Hibernate button.

---

## Verification

Run under UEFI (OVMF) qemu. **No rebuild happens in this branch** — these run after the
maintainer rebuilds with this branch merged.

- **T1 — unencrypted GUI (regression):** must still boot to SDDM after C2/C3. Check
  `/proc/cmdline` = `quiet loglevel=3 vt.global_cursor_default=0 splash rw root=UUID=…`.
- **T2 — encrypted GUI (the payoff):** erase + Encrypt → passphrase → reboot → initramfs unlock
  → SDDM. Then the two named runtime checks (both previously unverifiable statically):
  - **(i) kernel-install consumed the conf.d drop-in:** `lsinitcpio` the GUI-built initramfs
    (under the BLS `$ESP/<machine-id>/<ver>/` path) and `grep -E 'encrypt|cryptsetup'` — must be
    non-empty. Proves the `kernel-install`-driven `mkinitcpio` read `/etc/mkinitcpio.conf.d/devos.conf`
    and included the `encrypt` hook (C2 reaches the GUI path).
  - **(ii) passphrase-prompt count (F30):** record whether boot shows a **single** or **double**
    passphrase prompt. Single = clean. Double = the redundant root `crypttab` line. **Observe
    only — make no preemptive crypttab change**; a fix is a follow-up if it double-prompts.
  - Also verify: `/proc/cmdline` has `cryptdevice=UUID=…:<m> root=/dev/mapper/<m>`; ESP is plain
    FAT32 (unencrypted).
- **T3 — CLI unencrypted:** unchanged; `timeout 3` fallback reachable.
- **Guard test (C4):** `cryptsetup open` a partition, mount the mapper at `/mnt`, run
  `install.sh` → expect the clean refusal.
- **NVMe:** repeat T1/T2 with an emulated `nvme` drive (p1 suffix).

## Rollback
Each change is a small additive token/line/key: revert the `cryptsetup` line, the `encrypt`
token (×2), the `bootloader.conf` keys, the guard, and the `suspend` line. No data/format
migration.
