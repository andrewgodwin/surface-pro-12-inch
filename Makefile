DESTDIR ?=
GRUBD   := $(DESTDIR)/etc/default/grub.d
MODLD   := $(DESTDIR)/etc/modules-load.d
UDEVD   := $(DESTDIR)/etc/udev/rules.d
DRACUTD := $(DESTDIR)/etc/dracut.conf.d
PWD_USER := $(HOME)/.config/pipewire/pipewire.conf.d

FILES := \
	cpufreq/scmi-cpufreq.conf:$(MODLD)/scmi-cpufreq.conf \
	cpufreq/grub.cfg:$(GRUBD)/zz-surface-cpufreq.cfg \
	pm/grub.cfg:$(GRUBD)/zz-surface-pm.cfg \
	input/90-no-lid-wake.rules:$(UDEVD)/90-surface-no-lid-wake.rules \
	luks/dracut.conf:$(DRACUTD)/50-surface-luks.conf \
	firmware/dracut.conf:$(DRACUTD)/surface-pro-12-firmware.conf \
	luks/grub.cfg:$(GRUBD)/zz-surface-luks.cfg

LEGACY := $(GRUBD)/zz-local.cfg $(UDEVD)/90-no-lid-wake.rules \
	$(DRACUTD)/99-surface-luks-convert.conf $(DESTDIR)/usr/local/sbin/surface-luks-convert \
	$(GRUBD)/zz-surface-splash.cfg \
	$(DESTDIR)/lib/firmware/qcom/x1e80100/X1P42100-Microsoft-Surface-Pro-12in-tplg.bin

.PHONY: install uninstall apply initrd user user-uninstall

install:
	@for f in $(FILES); do install -Dm644 $${f%%:*} $${f#*:}; echo "$${f#*:}"; done
	rm -f $(LEGACY)
	DESTDIR=$(DESTDIR) sh wifi/fixwifi.sh
	@[ -n "$(DESTDIR)" ] || $(MAKE) --no-print-directory apply

uninstall:
	rm -fv $(DESTDIR)/lib/firmware/ath12k/WCN7850/hw2.0/board.bin
	@for f in $(FILES); do rm -fv $${f#*:}; done
	@[ -n "$(DESTDIR)" ] || $(MAKE) --no-print-directory apply

apply: initrd
	update-grub
	udevadm control --reload
	udevadm trigger --action=bind --subsystem-match=platform --sysname-match=gpio-keys || true
	modprobe scmi-cpufreq || true

initrd:
	dracut -f --kver $$(uname -r)

# Per-user (run without sudo). Needs swh-plugins.
user:
	@dpkg -s swh-plugins >/dev/null 2>&1 || { echo "apt install swh-plugins first"; exit 1; }
	install -Dm644 audio/60-surface-speaker-boost.conf $(PWD_USER)/60-surface-speaker-boost.conf
	systemctl --user restart pipewire pipewire-pulse wireplumber

user-uninstall:
	rm -f $(PWD_USER)/60-surface-speaker-boost.conf
	systemctl --user restart pipewire pipewire-pulse wireplumber
