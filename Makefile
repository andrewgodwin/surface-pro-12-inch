DESTDIR ?=
MODLD   := $(DESTDIR)/etc/modules-load.d
UDEVD   := $(DESTDIR)/etc/udev/rules.d
HWDBD   := $(DESTDIR)/etc/udev/hwdb.d
DRACUTD := $(DESTDIR)/etc/dracut.conf.d
FWDIR   := $(DESTDIR)/usr/lib/firmware/qcom/x1p42100/Microsoft
PLYD    := $(DESTDIR)/etc/plymouth
PWD_USER := $(HOME)/.config/pipewire/pipewire.conf.d
# Unused here, and iscsi-initiator-utils' NetworkManager dispatcher script
# queues `reload iscsi.service` on every interface up; that job is ordered
# after network-online.target, and remote-fs.target after it, so logins wait
# for Wi-Fi to connect (~16 s at boot).
MASK := iscsi.service

FILES := \
	cpufreq/scmi-cpufreq.conf:$(MODLD)/scmi-cpufreq.conf \
	input/61-type-cover-fn.hwdb:$(HWDBD)/61-surface-type-cover-fn.hwdb \
	luks/dracut.conf:$(DRACUTD)/50-surface-luks.conf \
	firmware/dracut.conf:$(DRACUTD)/surface-pro-12-firmware.conf \
	plymouth/plymouthd.conf:$(PLYD)/plymouthd.conf

.PHONY: install uninstall apply initrd firmware user user-uninstall

install:
	@rm -fv $(UDEVD)/90-surface-no-lid-wake.rules  # earlier versions
	@for f in $(FILES); do install -Dm644 $${f%%:*} $${f#*:}; echo "$${f#*:}"; done
	@[ -f $(FWDIR)/Surface12/qcadsp8380.mbn ] || $(MAKE) --no-print-directory firmware
	DESTDIR=$(DESTDIR) sh wifi/fixwifi.sh
	@[ -n "$(DESTDIR)" ] || { sh boot/setup-boot.sh install && systemctl mask $(MASK) && $(MAKE) --no-print-directory apply; }

uninstall:
	rm -fv $(DESTDIR)/usr/lib/firmware/ath12k/WCN7850/hw2.0/board.bin
	@for f in $(FILES); do rm -fv $${f#*:}; done
	@[ -n "$(DESTDIR)" ] || { sh boot/setup-boot.sh uninstall && systemctl unmask $(MASK) && $(MAKE) --no-print-directory apply; }

# Non-redistributable ADSP/CDSP/GPU-zap blobs from Windows; 7z asks for the
# password (AES zip, so it needs 7z: dnf install 7zip).
# Alternative: firmware/extract-windows.sh from a Windows partition.
firmware:
	mkdir -p $(FWDIR)
	7z x -y -o$(FWDIR) firmware/surface12-firmware.zip
	-restorecon -R $(FWDIR)

apply: initrd
	-restorecon -R /etc/modules-load.d /etc/udev /etc/dracut.conf.d /usr/lib/firmware
	systemd-hwdb update
	udevadm control --reload
	udevadm trigger --action=bind --subsystem-match=platform --sysname-match=gpio-keys || true
	udevadm trigger --action=change --subsystem-match=input || true
	modprobe scmi-cpufreq || true

initrd:
	dracut -f --regenerate-all

# Per-user (run without sudo). Needs ladspa-swh-plugins.
user:
	@rpm -q ladspa-swh-plugins >/dev/null 2>&1 || { echo "dnf install ladspa-swh-plugins first"; exit 1; }
	install -Dm644 audio/60-surface-speaker-boost.conf $(PWD_USER)/60-surface-speaker-boost.conf
	systemctl --user restart pipewire pipewire-pulse wireplumber

user-uninstall:
	rm -f $(PWD_USER)/60-surface-speaker-boost.conf
	systemctl --user restart pipewire pipewire-pulse wireplumber
