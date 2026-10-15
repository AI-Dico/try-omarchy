# Proposal: run upstream Omarchy inside a thin shell

Status: research, 2026-10-15. Nothing here has been tested in our VM yet; the
findings come from upstream code, package indexes and upstream CI.

## Summary

Try Omarchy should become a thin shell around a normal, upstream-managed
Omarchy install. Upstream merged the pieces this needs in the last week. The
one real limit is that on ARM, Omarchy is only published on the **edge**
channel for now.

## What upstream has as of today

- **[omarchy#14431](https://github.com/omacom/omarchy/pull/14431) (merged
  2026-10-12)** added proper ARM support to Omarchy:
  - Platform detection (`omarchy-hw-platform`): `x86`, `aarch64`,
    `aarch64-apple` and a few others. A QEMU `virt` VM counts as plain
    `aarch64`.
  - ARM package lists (`omarchy-pkg-defaults`) and ARM pacman templates
    (`default/pacman/aarch64/`).
  - Lifecycle dispatch (`docs/lifecycle-dispatch.md`): plain `aarch64`
    registers no platform package, so it takes the normal boot path (Limine,
    snapshots, `omarchy update`) with no Mac-specific boot code involved.
- **[omarchy-pkgs](https://github.com/omacom/omarchy-pkgs)** publishes ARM
  builds at `https://pkgs.omarchy.org/edge/aarch64`:
  - `omarchy` 4.0.4, `omarchy-dev`, `omarchy-settings`, `hyprland` 0.56.2,
    walker and the rest.
  - `linux-omarchy` 7.2.8 for ARM. Its kernel config
    (`pkgbuilds/linux-omarchy-aarch64/config.aarch64`) enables virtio (disk,
    net, GPU, input, sound, vsock), 9p, the EFI stub and 4K pages, so it should
    boot in our VM unchanged.
  - **rc and stable don't carry `omarchy` for ARM yet.** The templates say
    those come "once a release supports aarch64".
  - Base Arch Linux ARM packages come from `arm-mirror.omarchy.org`, a mirror
    of the live repos with no frozen snapshot. Every channel shares it.
- **[omarchy-iso#258](https://github.com/omacom/omarchy-iso/pull/258) (merged
  2026-10-15)** builds one ARM ISO for every board. Upstream CI installs it
  unattended in QEMU and boots the result. The unattended install reads its
  answers from a second drive labeled `cidata`
  (`configs/airootfs/usr/local/bin/omarchy-cidata-load`).
  - Nightly builds only publish x86 so far, including a ready-made `.qcow2` VM
    image (`https://nightly.omarchy.org/edge/latest.json`). The ARM ISO isn't
    published yet.

## Why our current setup is fragile

Updates aren't actually blocked in the guest. They're held back in three ways,
and that's where the mess comes from:

- **Omarchy isn't installed as a package.** We copy a pinned git tree into the
  image and register a stand-in package that claims to be `omarchy`
  (`try-omarchy-runtime`, `guest/scripts/register-omarchy-runtime.sh`).
- **We patch Omarchy's own files.** About 20 patches live in
  `guest/patches/omarchy`, and three Omarchy commands are replaced outright in
  `guest/native-overlay/usr/bin/`.
- **Key packages are frozen.** `IgnorePkg` in `guest/pacman.aarch64.conf`
  holds the kernel, Hyprland and Aquamarine, and our Hyprland is a custom
  build.
- **A hook undoes Omarchy's repo settings.**
  `guest/fragments/pre-refresh-pacman-restore-arm.sh` puts our `pacman.conf`
  back after Omarchy rewrites it.
- **The kernel lives outside the guest's control.** The app pulls the kernel
  and initramfs out of the disk and boots them directly
  (`macos/run-qemu-gpu.sh`), so the guest can't update its own kernel.
- **That's why we need our own migration system.** The checks in
  `GuestBootFixes.swift` and `guest/migrations/catalog.json` exist only
  because the guest can't fix itself through updates.

## Recommended design

1. **Let the guest own its boot.** Boot through UEFI firmware into Limine,
   exactly as upstream does on plain ARM machines, instead of loading the
   kernel directly. The firmware (`edk2-aarch64-code.fd`) is in the QEMU source
   we already build; we just need to ship it. This lets the kernel update
   normally. It also gives users Omarchy's snapshot-before-update and rollback
   from the boot menu, which needs btrfs (our image is ext4 today) and is the
   main safety net once people update freely.

2. **Build the base disk with Omarchy's real installer.** Run the official ARM
   ISO unattended (the `cidata` answers drive) in CI, then seal the result into
   a VM image. That's the same pipeline upstream uses for its x86 nightly
   images (`test/vm-image/vm-seal` in omarchy-iso). Once upstream publishes ARM
   VM images, which is a small step from #258, the app could download the
   official image and check its checksum. try-omarchy lives in the same omacom
   org, so it's worth asking them for this directly.

3. **Make Omarchy a real pacman package.** Then `omarchy update` and
   `omarchy-channel-set` work natively. Users can follow edge, or dev, which
   tracks a git checkout and can follow any branch or commit. Stable and rc
   appear once upstream publishes ARM to them.

4. **Move everything we add into one package, e.g. `try-omarchy-guest`.**
   That includes the clipboard, audio, camera, battery, Touch ID and timezone
   bridges, the udev rules, the fcitx defaults and the battery driver module.
   The one rule: it never edits files owned by the `omarchy` package. It
   customizes through config overrides, systemd drop-ins, environment files
   and Omarchy's own update hooks (`omarchy-hook post-update`). The app ships
   the package to the guest over the existing shared folder, so the
   guest-side version always matches the app it talks to.

5. **Sort the existing patches into three groups.**
   - **Upstream them.** These are now generic ARM issues: the
     `*-aarch64-unavailable` set, ghostty and 1Password on arm64, the
     QtQuick 6.11 workaround and the ARM kernel restart fix.
   - **Rewrite them as add-ons.** These include the Touch ID menu, mirroring
     the macOS timezone, the macOS power profile and the keyboard
     preselection.
   - **Drop them.** Upstream already covers some, including the Hyprland
     rounded-border patch. If one still matters, it goes to omarchy-pkgs,
     which already carries Aquamarine patches.

   After this, the migration system shrinks to "is `try-omarchy-guest`
   installed and current?" Omarchy's own migrations run through
   `omarchy update`.

6. **Add guardrails, since users can now change anything.**
   - Btrfs snapshots before every update.
   - Keep the app's ability to boot a recovery kernel.
   - A nightly CI job that installs the latest edge Omarchy plus our package
     and checks every connection between the app and the guest, so we catch
     upstream breakage before users do.

## Risks to accept

- **Edge only on ARM.** Every ARM user is on edge until upstream ships ARM to
  stable.
- **No frozen base repos.** All channels share the live Arch Linux ARM repos,
  so snapshots and rollback are the safety net, not version pins.
- **No in-place conversion for existing users.** Their disks are ext4, have no
  boot partition and use the stand-in package. The realistic path is to create
  a new VM, copy the home folder over, and keep the old disk until the user
  deletes it.

## Suggested first step

A one- to two-day spike before committing to this:

1. Build the ARM ISO from omarchy-iso `master` (`--arch aarch64`).
2. Install it unattended in our QEMU/HVF setup with UEFI and VirGL.
3. Record what breaks with none of our patches applied.

That gives the real patch list and confirms the GPU path works.
