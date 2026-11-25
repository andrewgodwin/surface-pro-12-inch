# Notes for porting this repo to Fedora 45

Written 2026-11-25 from the Ubuntu 26.10 Concept install (kernel `7.3.0-31-qcom-x1e`, Plasma 6.7.5), just before a wipe. These notes are for whoever, human or Claude, sets up Fedora on this machine. Anything marked **verify** is a guess that hasn't been tested on Fedora.

## Hardware and kernel facts that carry over unchanged
- **SoC and storage:**
  - SoC: X1P42100 (Purwa). Adreno X1-45 (`gen71500`), msm/freedreno/turnip.
  - Storage is UFS (`ufs_qcom`), which shows up as `sda`.
  - Wi-Fi: WCN7850 on ath12k, PCI `17cb:1107`, subsystem `17cb:3378`.
- **Device tree:** required, because boot is DT-only.
  - `boot/dtb` (sha256 `d7ed4b07…`) is the copy from harrisonvanderbyl's repo, which is what has been running. It differs from Ubuntu's packaged `x1p42100-microsoft-sp12in.dtb`, but their audio nodes are identical.
  - Upstream DTS: "arm64: dts: qcom: Add Microsoft Surface Pro 12in", v2 posted May 2026. **Verify** whether it's in Fedora's kernel, i.e. whether `/boot/dtb-$(uname -r)/qcom/x1p42100-microsoft-sp12in.dtb` exists.
- **`scmi-cpufreq` has no modalias**, so it never autoloads. Without it there are no cpufreq policies: the CPU runs at firmware-chosen clocks and idle draw is about 1 W higher. `cpufreq/scmi-cpufreq.conf` (modules-load.d) applies to any distro.
- **Interconnect votes and suspend power:**
  - Symptom: icc `sync_state` never runs, so boot-time INT_MAX interconnect votes stay in place. cxsd/ddr/aosd are then never entered in suspend.
  - Blockers: `1dfa000.crypto` has no driver (`CONFIG_CRYPTO_DEV_QCE` is unset in the Ubuntu kernel), and `3d6a000.gmu` is never driver-bound (this one blocks gcc/gpucc).
  - Fix: `fw_devlink.sync_state=timeout`.
  - **Verify** whether Fedora builds QCE (`modinfo qcrypto`). Then check the boot log for `sync_state() pending` and whether `/sys/kernel/debug/qcom_stats/cxsd` increments across a suspend. Keep the parameter unless both blockers are gone.
- **`clk_ignore_unused pd_ignore_unused`** were Ubuntu Concept defaults (`/etc/default/grub.d/ubuntu-x1e-settings.cfg`) and aren't needed: boot, display, touch, pen, suspend and audio all work without them. Fedora won't add them, so there's nothing to do.
- **Other Ubuntu Concept defaults never tested without:** `efi=noruntime`, `cma=128M`, and `GRUB_BADRAM="0x8800000000,0xf800000000"`. **Verify** each on Fedora. If boot or suspend breaks, add them back with `grubby`. The BADRAM entry can be expressed as `memmap=` if needed.
- **Lid switch, spurious wakes:** gpio-keys `switch-lid` (TLMM gpio2, via PDC) spuriously wakes the machine from CX collapse. `input/90-no-lid-wake.rules` disables gpio-keys wakeup. It needs `ACTION=="add|bind"`, because the `gpio_keys` module probe re-enables wakeup. The power button (`pmic_pwrkey`) still wakes.
- **Lid switch, close never registers:** the falling edge raises no IRQ. The level goes low but the IRQ count doesn't move. Closing the lid therefore never triggers suspend; logind only sees the close at the next resume. Suspected cause is PDC/TLMM dual-edge handling. This is a kernel issue: check whether a new kernel fixes it before working around it.
- **Type cover Fn:** it sends HID usage 0x10097, which maps to `BTN_0`, and libinput treats that as a held mouse button. `input/61-type-cover-fn.hwdb` remaps it to `KEY_FN`. Applies unchanged to Fedora.
- **Speakers:**
  - Hardware: 2× WSA8845 on SoundWire `swr0` and the WSA macro.
  - They work, but the kernel caps PA and WSA RX digital volume at 0 dB, and VI sense is off, so there's no speaker protection.
  - `audio/60-surface-speaker-boost.conf` is a PipeWire filter-chain: sc4 at −18 dB 2:1 with +9 dB make-up gain, then a fast lookahead limiter at −1 dBFS. Measured: +9 dB below the threshold, and a full-scale sine comes out at −1 dBFS peak.
  - Don't add `node.dont-reconnect`: the filter disappears if it starts before the ALSA sink exists.
  - Don't raise the kernel caps.
- **Unexplained ~5 h wakes from suspend:** source still unknown. Next step: `echo 1 > /sys/power/pm_debug_messages`, then look for `PM: Triggering wakeup from IRQ N` in the kernel log.
- **Benign noise:**
  - `i2c_hid_of 0-0016` resume error −6 (the touchscreen still works).
  - PCIe4 L2 timeout.
  - `qcom-apm CMD timeout` at boot.
  - ASoC "no matching ACPI device found".
- **Plasma lock-screen bug:** suspending with the lock screen up logs `pam_unix(kde:auth): conversation failed` on every suspend, and the lock screen then runs its "wrong password" retry delay. Applies to the Fedora KDE edition too. Not hardware-related; not reported upstream yet.

## What changes on Fedora

### Boot and device tree
- **Kernel image:** Ubuntu's was a stubble PE with `.dtbauto` sections and no SP12 entry, so it relied on GRUB `devicetree /boot/dtb` plus `stubble.dtb_override=true`. Fedora's kernel is a plain arm64 Image, so `stubble.dtb_override` goes away.
- **Loading the DTB:** Fedora uses GRUB plus BLS (`/boot/loader/entries/*.conf`). A BLS entry accepts a `devicetree /path` line.
  - With an upstream DTB: point it at `/dtb-<ver>/qcom/x1p42100-microsoft-sp12in.dtb`.
  - Otherwise: copy `boot/dtb` to `/boot/` and reference that.
  - New kernels need it too. Either add a `/etc/kernel/install.d` plugin that adds the `devicetree` line to each new entry, or use the GRUB `devicetree` command globally in `/etc/grub.d/40_custom`. **Verify** which one Fedora's BLS GRUB honours.
- **Live USB:** same chicken-and-egg as on Ubuntu. Edit GRUB at the USB boot prompt to add `devicetree`; the DTB has to be on a readable FAT or ext partition. Then put the DTB in place in the installed system before its first boot. Check first whether the Fedora 45 aarch64 image already ships the SP12 DTB.
- **Kernel arguments:** use `grubby --update-kernel=ALL --args="…"`, not `/etc/default/grub.d` fragments. Fedora has no grub.d drop-ins and `update-grub` doesn't exist. `/etc/default/grub` `GRUB_CMDLINE_LINUX` only seeds new installs.
  - So `cpufreq/grub.cfg`, `pm/grub.cfg` and `luks/grub.cfg` become `grubby` calls in the Makefile.
  - Wanted: `fw_devlink.sync_state=timeout`, plus `cpufreq.default_governor=schedutil` only if Fedora's default isn't already schedutil (check `scaling_governor`).
- **Secure Boot:** Fedora's kernel is signed. GRUB lockdown blocks `devicetree` under Secure Boot exactly as on Ubuntu, so Secure Boot still needs a DTB embedded in a signed image (a UKI with `.dtb`, MOK-signed).
  - Firmware state: Setup Mode, with no PK/KEK/db.

### LUKS
- Anaconda does LUKS2 with a separate `/boot` natively, and it writes `rd.luks.uuid` and crypttab itself. `luks/grub.cfg` is therefore obsolete; don't port it.
- Fedora's GRUB may not do argon2 either, so keep `/boot` unencrypted.
- dracut is native, but Fedora builds **hostonly** initrds. Keep `luks/dracut.conf` `force_drivers` (`surface_aggregator*`, `surface_hid*`, `hid_generic`, `hid_multitouch`, plus `dm_crypt`, `aes_ce_blk`) so the type cover works at the passphrase prompt. Without them the cover doesn't work there.
- Verified on Ubuntu: keyboards register about 2.0–2.4 s after boot, before switch-root.
- The installer needs the cover too. **Verify** that the cover works in Anaconda.
- Plymouth: Fedora defaults to `rhgb quiet`. The bgrt theme falls back to a spinner, because there's no ACPI BGRT.

### Firmware
- Fedora compresses firmware with **xz**, not zst, and splits linux-firmware into subpackages (`qcom-firmware`, `atheros-firmware`, …).
- `firmware/dracut.conf` hard-codes `gen71500_*.zst`. Change it to globs, e.g. `/usr/lib/firmware/qcom/gen71500_*`.
  - These must be in the initrd: the msm GPU, ADSP/CDSP and iris load before root is mounted and fail with −ENOENT otherwise.
- **Windows DSP firmware:** `firmware/extract-windows.sh` copies ADSP/CDSP/GPU-zap blobs from the Windows DriverStore into `qcom/x1p42100/Microsoft/Surface12/`. These blobs are not redistributable. Back that directory up before wiping. If Windows (`sda3`) is wiped too, there's no source left.
  - Check `extract-windows.sh` against Fedora: it needs ntfs3 (in-kernel) and the NTFS partition.
- **Audio topology:** `qcom/x1e80100/X1P42100-Microsoft-Surface-Pro-12in-tplg.bin` came from Ubuntu's linux-firmware. **Verify** it's in Fedora's `qcom-firmware`; copy it from this repo or from Ubuntu if missing.
- **UCM:** `ucm2/Qualcomm/x1e80100/MICROSOFT-Surface-Pro-12in.conf` was added in alsa-ucm-conf 1.2.15. Fedora 45 should have it.
- **Wi-Fi:** `wifi/fixwifi.sh` extracts the `subsystem-device=3378` board from `board-2.bin` into `board.bin`.
  - It handles `.zst` only. Add `xz -dc "$SRC.xz"` for Fedora.
  - **Verify** first whether Fedora's linux-firmware now has a `17cb:1107/17cb:3378` entry (`dmesg | grep ath12k` showing a board-file error means it doesn't).

### Packages and Makefile
- Makefile changes:
  - `update-grub` → `grubby` (see above).
  - `dpkg -s swh-plugins` → `rpm -q ladspa-swh-plugins`. **Verify** the package name; the plugins land in `/usr/lib64/ladspa`, and filter-chain finds them by `plugin = sc4_1882` from that search path.
- Paths that don't change: `modules-load.d`, `udev/rules.d`, `udev/hwdb.d`, `dracut.conf.d`, `~/.config/pipewire`. `systemd-hwdb update`, the `udevadm` calls and `dracut -f --kver` also work as is.
- The `/lib` paths in the Makefile and scripts work through Fedora's usrmerge symlinks, but writing `/usr/lib` is cleaner.
- `LEGACY` lists Ubuntu-only leftovers. Drop it.

### Kernel config to check
- Run `grep` on `/boot/config-$(uname -r)` for these:
  - `SURFACE_AGGREGATOR*` and `SURFACE_HID*` (needed for the type cover)
  - `SURFACE_AGGREGATOR_TABLET_SWITCH`
  - `ARM_SCMI_CPUFREQ`
  - `SND_SOC_X1E80100`, `SND_SOC_WSA884X`, `SOUNDWIRE_QCOM`
  - `QCOM_IRIS`
  - `ATH12K`
  - `CLK_X1P42100_GPUCC` and `CLK_X1P42100_VIDEOCC` (or whatever the Purwa clock controllers are called)
  - `UFS_QCOM`
  - `CRYPTO_DEV_QCE`
- Modules loaded on the working Ubuntu system included:
  - Clocks: `camcc_x1p42100`, `gpucc_x1p42100`, `videocc_x1p42100`, `dispcc_x1e80100`
  - Audio: `snd_soc_x1e80100`, `snd_soc_wsa884x`, `snd_soc_sdca`, `soundwire_qcom`, `q6apm_*`
  - Surface: `surface_aggregator*`, `surface_hid*`, `surface_temp`, `surface_aggregator_tabletsw`
  - Wi-Fi: `ath12k` + `ath12k_wifi7`
  - Others: `qcom_iris`, `qcom_battmgr`, `ucsi_glink`, `pmic_glink_altmode`, `scmi_cpufreq`, `qcomtee`, `fastrpc`
- Anything missing on Fedora points to a kernel config gap and can't be fixed from userspace.
