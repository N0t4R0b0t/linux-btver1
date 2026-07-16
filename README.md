# linux-btver1

A CPU-tuned, slimmed Linux kernel package for the **Acer Aspire 725 (AMD C-60
APU, "Bobcat" core, x86_64)** running Arch Linux. Built to be consumed by
[pkgmirror](https://github.com/N0t4R0b0t/customArchForArch)'s `btver1` repo
(or built standalone in its x86_64 build chroot).

## Why

The stock Arch kernel is built generic. On a low-power dual-core Bobcat, and
on a machine with only 3.5GB RAM, a slimmer kernel means faster boot and more
free RAM. So this package:

1. **Tunes for Bobcat** via `KCFLAGS="-march=btver1 -mtune=btver1"` in
   `build()` — **not** a Kconfig option. Unlike i686 (`linux-atom`'s
   `CONFIG_MATOM`), x86_64 kernels have no per-CPU-model Kconfig choice any
   more; the closest equivalent, `CONFIG_X86_NATIVE_CPU` (`-march=native`),
   detects whatever CPU is running the *compiler* — wrong for cross-building
   in pkgmirror's chroot, which doesn't run on real Bobcat hardware.
   `-march=btver1` is a real, named, portable GCC target, so it works
   correctly regardless of what CPU actually builds it.
2. **Slims** the config (by default) to just the drivers the machine actually
   loads, via `make localmodconfig` against a captured module list.

It is **co-installable with the stock `linux`** — `pkgbase=linux-btver1` and
`CONFIG_LOCALVERSION="-btver1"`, so it installs as `vmlinuz-linux-btver1` with
its own modules dir. Keep the stock kernel as a fallback boot entry until you
trust this one.

## Files

| File          | What                                                                 |
|---------------|----------------------------------------------------------------------|
| `PKGBUILD`    | builds `linux-btver1` (+ headers) from a kernel.org tree with `config` |
| `config`      | the machine's **own running config**, retuned: `-btver1` localversion |
| `lsmod.btver1`| the machine's loaded modules — input for `localmodconfig` slimming, captured **with the USB WiFi dongle plugged in** (the onboard Realtek `rtl8723ae` is old/unreliable per the machine owner, so the dongle's `mt76x0u`/`mt76`/`mt76x02_*` stack must survive slimming) |
| `tune-config.sh` | reproduces the config transform from any base config               |
| `linux-btver1-grub.hook` | pacman hook, fires on install/upgrade of this package       |
| `linux-btver1-grub-update` | script the hook runs — regenerates GRUB's menu safely     |

## Building

**Through pkgmirror** (recommended): point it at this repo directly —

```bash
bin/add-package.sh btver1 linux-btver1 --source git \
  --url https://github.com/N0t4R0b0t/linux-btver1.git
```

or via the dashboard: add-package with source `git (custom repo)`. Every
build pulls this repo fresh. Slimming is on by default — pkgmirror has no
reliable way to pass a custom env var like `SLIM` through `makechrootpkg`'s
fixed `--preserve-env` allowlist.

**Locally**, in an x86_64 chroot (the pkgmirror `btver1` chroot is ideal):

```bash
makepkg -s              # tuned + slimmed (the default)
SLIM=0 makepkg -s       # tuned only, full config — for comparison/debugging
```

Before the first build, pin the kernel version and refresh checksums:

```bash
updpkgsums     # fills the SKIP sha256sums
```

## Slimming caveat

`localmodconfig` keeps only modules present in `lsmod.btver1` (captured at one
point in time) plus dependencies. Anything **not loaded at capture** (a USB
device you hadn't plugged in, a filesystem you rarely mount) gets dropped.
Re-capture `lsmod` with all your hardware attached — **especially the WiFi
dongle** — before relying on the slimmed build, and always keep the stock
kernel as a fallback.

**Applied proactively (2026-07-15), learned the hard way on `linux-atom`
first**: no USB keyboard/mouse was plugged in when `lsmod.btver1` was
captured either (only `mac_hid`, a virtual remapping driver, shows up — no
`usbhid`/`hid_generic` at all). This isn't just "this machine doesn't need
it" — `mkinitcpio`'s own `keyboard` hook expects `usbhid` to exist and
**fails the initramfs build without it**. `pkgrel=1` already force-enables
`CONFIG_USB_HID`/`CONFIG_HID`/`CONFIG_HID_GENERIC`/`CONFIG_USB_HIDDEV` after
the `localmodconfig` step regardless of what the capture saw.

## Installing (GRUB, not syslinux)

This machine boots via legacy BIOS GRUB, unlike the Aspire One's syslinux.
GRUB behaves very differently on a new-kernel install: it never
auto-regenerates its menu (so a newly installed kernel is invisible until
`grub-mkconfig` runs), but *when* it does regenerate, it rebuilds the **whole**
menu from a fresh scan of `/boot` — and with the stock `GRUB_DEFAULT=0`
(boot the topmost entry), simply adding a new kernel and regenerating could
silently make it the new default with no explicit choice involved.

`linux-btver1-grub-update` (installed as a pacman hook,
`91-linux-btver1-grub.hook`) handles this safely, one-time-only:
1. If the machine is still on the stock index-based default (`GRUB_DEFAULT=0`,
   not yet `saved`), it captures the **title** of whatever's currently
   booting by default from the existing `grub.cfg`, switches
   `/etc/default/grub` to `GRUB_DEFAULT=saved` + `GRUB_SAVEDEFAULT=true`, and
   pins that title as the saved default via `grub-set-default`.
2. Then runs `grub-mkconfig -o /boot/grub/grub.cfg` to actually add the new
   kernel's menu entry.

Because the default is pinned by **title** (not position) and only ever set
once (skipped entirely if `GRUB_DEFAULT=saved` is already present — whether
we set it or you did), this can't silently flip what boots by default, either
on this install or any future kernel package's regeneration. Select
"linux-btver1" manually from the GRUB menu to test it; the stock kernel keeps
booting by default until you explicitly change it (`grub-set-default` or
`grub-reboot`).

## CPU frequency: the BIOS hides the real turbo state (amdmsrtweaker)

The C-60 is rated for a `1.333GHz` turbo state, but this BIOS's ACPI `_PSS`
table only ever advertises two P-states to Linux — `1.0GHz` and `800MHz`.
`acpi-cpufreq` faithfully reports what the table says
(`cpuinfo_max_freq`/`scaling_max_freq` both cap at `1000000`), so the OS
never even knows the real turbo state exists. This is a known issue with
this CPU generation, not specific to this kernel build.

The fix isn't a kernel config option — it's
[amdmsrtweaker-lnx](https://github.com/johkra/amdmsrtweaker-lnx)
(`amdmsrt`), which writes AMD's P-state MSRs directly, bypassing what ACPI
advertises. This **restores already-validated stock silicon behavior**, it's
not an overclock: `P0=13.3334@1.125 P1=13.3334@1.125 P2=10@1.1 P3=@1.0`
(`13.3334 × 100MHz = 1.333GHz`, the chip's actual rated turbo). Confirmed
working: both cores go from a hard-capped `1000MHz` to a genuine `~1330MHz`
after applying it.

Automated via a systemd oneshot service (not part of this repo — `amdmsrt`
is a separate third-party tool, machine-specific install path):

```ini
[Unit]
Description=Restore AMD C-60 stock turbo P-state (BIOS ACPI _PSS table under-reports it)
After=multi-user.target

[Service]
Type=oneshot
ExecStartPre=/usr/bin/modprobe msr
ExecStart=/home/hellblazer/amdmsrtweaker-lnx/amdmsrt P0=13.3334@1.125 P1=13.3334@1.125 P2=10@1.1 P3=@1.0
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

`systemctl enable --now amd-pstate-tweak.service` applies it every boot.

**Thermal caveat, checked and worth taking seriously**: this machine's BIOS
dates to 2013, and idle CPU temp was already `67-68°C` (`k10temp`'s own
"high" watermark is `70°C`) *before* applying this fix — likely aged
thermal paste/dust after over a decade, not something specific to this
tweak. Even a light single-threaded load after restoring stock turbo pushed
it to `72.5°C`, past the "high" watermark (still well under the `100°C`
critical threshold, so not dangerous, just worth noting). **Deliberately not
pushing beyond the stock-validated values above** — going further into real
overclock territory on a machine already this thermally tight isn't worth
it without a physical cleaning first.