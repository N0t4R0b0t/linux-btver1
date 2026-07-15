#!/usr/bin/env bash
# tune-config.sh <base-config> [out]
#
# Reproduce the linux-btver1 config transform from any base kernel config (e.g. a
# fresh Arch `linux` config or the machine's /proc/config.gz): give it a distinct
# localversion. Unlike linux-atom (i686, where CONFIG_MATOM is a real per-model
# Kconfig choice), x86_64 kernels have no equivalent per-CPU-family Kconfig option
# any more -- arch/x86/Kconfig.cpu's processor-family "choice" block (MATOM, MK7,
# ...) only applies `depends on X86_32`. The 64-bit replacement, CONFIG_X86_NATIVE_CPU
# (-march=native), detects whatever CPU is running the COMPILER, which is wrong for
# cross-building in pkgmirror's chroot (different hardware than the real C-60) -- so
# CPU tuning here comes entirely from KCFLAGS in the PKGBUILD's build() step
# (KBUILD_CFLAGS += $(KCFLAGS), Makefile:1132), not from a Kconfig setting.
# Slimming (localmodconfig) is a separate build-time step (SLIM=1 in the PKGBUILD)
# since it needs the kernel tree.
set -euo pipefail

base="${1:?usage: tune-config.sh <base-config> [out]}"
out="${2:-config}"
[ -f "$base" ] || { echo "no such file: $base" >&2; exit 1; }

sed -e 's/^CONFIG_LOCALVERSION="[^"]*"/CONFIG_LOCALVERSION="-btver1"/' \
    "$base" > "$out"

grep -q '^CONFIG_LOCALVERSION=' "$out" || printf 'CONFIG_LOCALVERSION="-btver1"\n' >> "$out"

echo "wrote $out"
grep -E '^CONFIG_LOCALVERSION=' "$out"