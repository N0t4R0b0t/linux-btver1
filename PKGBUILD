# Maintainer: N0t4R0b0t
# linux-btver1 — a CPU-tuned, slimmed Linux kernel package for the Acer Aspire
# 725 (AMD C-60 APU, "Bobcat" core, x86_64) running Arch Linux.
#
# Co-installable with the stock `linux` kernel: distinct pkgbase and
# CONFIG_LOCALVERSION="-btver1", so it installs as vmlinuz-linux-btver1 with
# its own modules dir. Keep the stock kernel as a fallback boot entry until
# you trust this one.
#
# Unlike linux-atom (i686, where CONFIG_MATOM is a real per-model Kconfig
# choice), x86_64 kernels have no equivalent per-CPU Kconfig option any more
# -- arch/x86/Kconfig.cpu's processor-family choice block only applies
# `depends on X86_32`. The 64-bit replacement, CONFIG_X86_NATIVE_CPU
# (-march=native), detects whatever CPU is running the COMPILER -- wrong when
# cross-building in pkgmirror's chroot (different hardware than the real
# C-60). So tuning here comes entirely from KCFLAGS in build() (Makefile:
# KBUILD_CFLAGS += $(KCFLAGS)), a real, portable -march=btver1, not Kconfig.
#
# Pinned to 7.1.3 to match ./config (the machine's own running config).
# Build it in an x86_64 chroot (the pkgmirror `btver1` chroot is ideal).
# Vanilla kernel.org tree.

pkgbase=linux-btver1
pkgname=("$pkgbase")
pkgver=7.1.3
pkgrel=3
_srcname=linux-${pkgver}
arch=('x86_64')
url="https://www.kernel.org/"
license=('GPL-2.0-only')
makedepends=('bc' 'cpio' 'gettext' 'libelf' 'pahole' 'perl' 'python' 'tar' 'xz')
options=('!strip')
source=(
  "https://cdn.kernel.org/pub/linux/kernel/v7.x/${_srcname}.tar.xz"
  config
  lsmod.btver1
  linux-btver1-grub.hook
  linux-btver1-grub-update
)
sha256sums=('be41c068e88f5242a19bccdbffbe077b18c47b45f627e2325504b4fab79dd1dc'
            'SKIP'
            'SKIP'
            'SKIP'
            'SKIP')

prepare() {
  cd $_srcname
  echo "Setting config..."
  cp ../config .config
  scripts/config --set-str CONFIG_LOCALVERSION "-btver1"
  # linux-atom's config already had CONFIG_DEBUG_INFO_NONE=y; this machine's
  # own captured config had full DWARF5+BTF debug info enabled instead. Real
  # consequence, not just build hygiene: BTF/DWARF5 generation blew past a
  # 10G tmpfs build-scratch mount ("No space left on device" during objcopy's
  # debug_info extraction) on a container with only 16GB total RAM -- kernel
  # debug symbols aren't needed for normal use, so disable at the source
  # (compiler-level) rather than keep growing tmpfs toward the RAM ceiling.
  scripts/config --disable CONFIG_DEBUG_INFO --disable CONFIG_DEBUG_INFO_BTF \
                  --disable CONFIG_DEBUG_INFO_BTF_MODULES \
                  --enable  CONFIG_DEBUG_INFO_NONE
  # Slim to only the modules this machine loads (aggressive; see README). On by
  # default -- an unslimmed build is only useful for local testing outside
  # pkgmirror (which has no reliable way to pass a custom env var like SLIM
  # through makechrootpkg's fixed --preserve-env allowlist), so build it with
  # `SLIM=0 makepkg -s` locally if you need the full config for comparison.
  if [ "${SLIM:-1}" != "0" ]; then
    make LSMOD="$srcdir/lsmod.btver1" localmodconfig
    # Lesson learned the hard way on linux-atom (2026-07-15): localmodconfig
    # only keeps what's loaded at lsmod-capture time -- no USB keyboard/mouse
    # was plugged in when lsmod.btver1 was captured either (only mac_hid, a
    # virtual remapping driver, shows up; no usbhid/hid_generic at all), and
    # mkinitcpio's own `keyboard` hook fails the initramfs build without
    # usbhid ("module not found: usbhid", "the image may not be complete").
    # Force USB HID support back on regardless of what the capture saw --
    # it's close to essential (any USB keyboard/mouse, plus early-boot input
    # generally), not a niche driver worth the aggressive slimming applied
    # elsewhere. Applying this proactively here, not after a failed install.
    scripts/config --enable CONFIG_USB_HID --enable CONFIG_HID \
                    --enable CONFIG_HID_GENERIC --enable CONFIG_USB_HIDDEV
    # Same lesson, different module: zram was never loaded at lsmod-capture
    # time (nothing on the machine used it yet), so localmodconfig strips
    # CONFIG_ZRAM even though the base config had it enabled. zram-generator
    # then fails at boot with "Module zram not found" -- force it back on
    # regardless of what the capture saw, same as USB HID above.
    scripts/config --module CONFIG_ZRAM
    # Third instance of the same lesson: no USB mass-storage device was
    # plugged in at lsmod-capture time either, so localmodconfig strips
    # CONFIG_USB_STORAGE. Result: USB drives enumerate fine (xhci_hcd/ehci
    # are builtin, so the controller and SuperSpeed negotiation both work),
    # but no driver binds to the Mass Storage interface ("Driver=[none]" in
    # lsusb -t) -- so no USB drive of any kind, USB2 or USB3, is usable.
    # Force it back on regardless of what the capture saw, same as above.
    scripts/config --module CONFIG_USB_STORAGE
  fi
  make olddefconfig
  make -s kernelrelease > version
  echo "Prepared $pkgbase version $(<version)"
}

build() {
  cd $_srcname
  # -march=btver1 (real AMD Bobcat target, portable -- unlike -march=native,
  # works correctly even though this chroot doesn't run on actual Bobcat
  # hardware) + -mtune=btver1 for instruction scheduling.
  make KCFLAGS="-march=btver1 -mtune=btver1" all
}

package() {
  pkgdesc="CPU-tuned (AMD Bobcat/C-60), slimmed Linux kernel for the Aspire 725"
  depends=('coreutils' 'initramfs' 'kmod')
  optdepends=('linux-firmware: firmware images for some devices'
              'wireless-regdb: correct wireless channels for your country')

  cd $_srcname
  local kernver="$(<version)"
  local modulesdir="$pkgdir/usr/lib/modules/$kernver"

  echo "Installing boot image..."
  # 'install' triggers the mkinitcpio pacman hooks, which read pkgbase for the name.
  install -Dm644 "$(make -s image_name)" "$modulesdir/vmlinuz"
  echo "$pkgbase" | install -Dm644 /dev/stdin "$modulesdir/pkgbase"

  echo "Installing modules..."
  ZSTD_CLEVEL=19 make INSTALL_MOD_PATH="$pkgdir/usr" INSTALL_MOD_STRIP=1 \
    DEPMOD=/doesnt/exist modules_install
  rm -f "$modulesdir"/{source,build}

  echo "Installing GRUB regeneration hook..."
  # GRUB (unlike syslinux) auto-detects every kernel in /boot on regenerate,
  # but never auto-regenerates on install -- and naively doing so risks
  # silently changing the default boot kernel (see linux-btver1-grub-update).
  install -Dm644 "$srcdir/linux-btver1-grub.hook" \
    "$pkgdir/usr/share/libalpm/hooks/91-linux-btver1-grub.hook"
  install -Dm755 "$srcdir/linux-btver1-grub-update" \
    "$pkgdir/usr/share/libalpm/scripts/linux-btver1-grub-update"
}