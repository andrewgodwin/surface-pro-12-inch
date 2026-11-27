#!/bin/sh
# Fedora GRUB/BLS boot config for Surface Pro 12in. Run by `make install`.
#   setup-boot.sh install     UKI plugin + UKIs for all kernels, kernel args
#   setup-boot.sh uninstall   remove the kernel args, the plugin, our UKIs and entries
#
# DTB: see 96-surface-uki.install. Each kernel gets a
# /boot/vmlinuz-<ver>-surface.efi (patched DTB with iris enabled) and a
# "(Surface)" GRUB entry, made the default; Fedora's stock entries are kept
# unmodified as the fallback (stub auto-selects the unpatched DTB on 7.3+).
#
# Kernel args: grub2-mkconfig rewrites every BLS entry's options (and
# /etc/kernel/cmdline) from GRUB_CMDLINE_LINUX whenever /etc/default/grub is
# newer than /etc/kernel/cmdline, so args go in both places.
set -eu
PLUGIN=/etc/kernel/install.d/96-surface-uki.install
# Force icc sync_state past driverless consumers (1dfa000.crypto: no QCE
# driver; 3d6a000.gmu: never bound) that otherwise pin interconnect votes at
# INT_MAX and block CX/DDR collapse in suspend. The timeout is the deferred
# probe timeout, which Fedora's kernel defaults to -1 (never), so set it; it
# restarts on every module load, so 30 s is counted from the last one.
# Firmware advertises a TPM2 Linux has no driver for here, so systemd waits
# ~45 s for /dev/tpm0 + /dev/tpmrm0, in the initrd and again after switch-root.
KARGS="fw_devlink.sync_state=timeout deferred_probe_timeout=30 systemd.tpm2_wait=0"
CFG=/etc/default/grub

set_var() {  # set_var NAME VALUE
	if grep -q "^$1=" "$CFG"; then
		sed -i "s|^$1=.*|$1=\"$2\"|" "$CFG"
	else
		echo "$1=\"$2\"" >>"$CFG"
	fi
}
cmdline() { sed -n 's/^GRUB_CMDLINE_LINUX="\(.*\)"$/\1/p' "$CFG"; }
kernels() { ls /lib/modules | sort -V; }

# Earlier versions of this repo: GRUB-loaded patched DTB (ignored by the
# stub), and a UKI signing key for Secure Boot.
cleanup_legacy() {
	rm -f /etc/kernel/install.d/60-surface-dtb.install /boot/dtb-*/qcom/x1p42100-microsoft-sp12in-surface.dtb
	rm -rf /etc/kernel/surface-uki
	sed -i '/^GRUB_DEVICETREE=/d' "$CFG"
	for e in /boot/loader/entries/*.conf; do
		sed -i '/^devicetree[[:space:]]/d' "$e"
	done
}

case "${1:-}" in
install)
	for t in fdtput ukify objcopy; do
		command -v $t >/dev/null || { echo "missing $t: dnf install dtc systemd-ukify systemd-boot-unsigned binutils" >&2; exit 1; }
	done
	cleanup_legacy
	c=$(cmdline)
	for a in $KARGS; do
		case " $c " in *" $a "*) ;; *) c="$c $a" ;; esac
	done
	set_var GRUB_CMDLINE_LINUX "$(echo $c)"
	grubby --update-kernel=ALL --args="$KARGS"
	install -Dm755 "$(dirname "$0")/96-surface-uki.install" "$PLUGIN"
	for v in $(kernels); do "$PLUGIN" add "$v"; done
	;;
uninstall)
	c=" $(cmdline) "
	for a in $KARGS; do c=$(echo "$c" | sed "s| $a | |g"); done
	set_var GRUB_CMDLINE_LINUX "$(echo $c)"
	grubby --update-kernel=ALL --remove-args="$KARGS"
	cleanup_legacy
	for v in $(kernels); do [ -x "$PLUGIN" ] && "$PLUGIN" remove "$v"; done
	rm -f "$PLUGIN"
	# Back to Fedora's newest stock entry.
	grub2-set-default "$(cat /etc/machine-id)-$(kernels | tail -1)"
	;;
*)
	echo "usage: $0 install|uninstall" >&2
	exit 1
	;;
esac
