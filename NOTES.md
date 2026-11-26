# Notes

Hardware facts and open issues, carried over from the Ubuntu 26.10 Concept install and updated on Fedora 45 (kernel 7.3.4-300.fc45, 2026-11-25).

## Hardware
- SoC: X1P42100 (Purwa); Adreno X1-45 (`gen71500`), msm/freedreno/turnip.
- Storage: UFS (`ufs_qcom`), shows up as `sda`. `sda3` is the Windows partition (a source for `firmware/extract-windows.sh`).
- Wi-Fi: WCN7850 on ath12k, PCI `17cb:1107`. Fedora's kernel reports subsystem `00ab:1414` (Ubuntu's notes said `17cb:3378`). `board-2.bin` matches neither, so `wifi/fixwifi.sh` extracts the 3378 board as `board.bin`.
- Speakers: 2× WSA8845 on SoundWire `swr0` and the WSA macro. The kernel caps PA and WSA RX digital volume at 0 dB and VI sense is off (no speaker protection). `audio/60-surface-speaker-boost.conf`:
  - It's a PipeWire filter-chain: sc4 at −18 dB 2:1 with +9 dB make-up gain, then a lookahead limiter at −1 dBFS.
  - Don't add `node.dont-reconnect`.
  - Don't raise the kernel caps.

## Boot on Fedora
- `kernel-uki-dtbloader` is a systemd-stub UKI with `.dtbauto` sections and `.hwids`, and 7.3.4 includes the SP12 DTB.
  - Auto-selection didn't work on 7.2.11, which also doesn't ship the DTB in `/boot/dtb-<ver>`.
  - On 7.3.4 the stub auto-selects the packaged DTB, and it overrides any DTB loaded by GRUB.
  - The default boot entry is our own UKI with a patched DTB (see below). Fedora's stock entries are left alone; 7.2's has no usable DTB, but its Surface entry gets the newest kernel's.
- Fedora's packaged DTB differs from harrisonvanderbyl's (`boot/dtb`). On Ubuntu the audio nodes were identical between the two, and firmware paths match.
- `grub2-mkconfig` rewrites every BLS entry's options from `GRUB_CMDLINE_LINUX` whenever `/etc/default/grub` is newer than `/etc/kernel/cmdline`, so kernel args must go in both places (`setup-boot.sh` does).
- Not used and apparently not needed: `clk_ignore_unused`, `pd_ignore_unused`, `efi=noruntime`, `cma=128M`, `GRUB_BADRAM="0x8800000000,0xf800000000"`. If boot or suspend breaks, try adding them back with grubby.
- Secure Boot doesn't work (tried 2026-11-25; left off):
  - With Secure Boot off, the Surface firmware reports Setup Mode with empty PK/KEK/db/dbx. Its keys only appear when a mode (e.g. "Microsoft & 3rd party CA") is selected, and switching back to off doesn't clear anything.
  - With "Microsoft & 3rd party CA", shim (16.1) and GRUB (2.12-83) load. Then both Fedora's stock signed UKI and our MOK-signed UKI go to a black screen with a `_` cursor, even with `earlycon=efifb keep_bootcon ignore_loglevel` and no `quiet`. There's no journal or pstore, so the kernel likely never starts. Suspect: GRUB's handoff to a UKI under Secure Boot.
  - A MOK from that attempt (`CN=Surface Pro 12 UKI signing key (rattata)`) is still enrolled; its private key has been deleted. To remove it: `mokutil --export`, then `mokutil --delete` the matching `MOK-*.der`, then confirm in MokManager on reboot.
  - Next idea: skip GRUB. A firmware boot entry runs shim with a UKI on the ESP as its second stage, with the initrd and cmdline embedded, signed with a MOK key. That would also cover the initrd, which GRUB loads unverified.

## Power
- `scmi-cpufreq` has no modalias, so it needs modules-load.d. Without it there are no cpufreq policies, and idle draw is about 1 W higher.
- icc `sync_state` blockers:
  - `1dfa000.crypto`: Fedora doesn't build `CRYPTO_DEV_QCE` either.
  - `3d6a000.gmu`: never bound.
  - Hence `fw_devlink.sync_state=timeout`.
  - **TODO:** check the boot log for `sync_state() pending`, and whether `/sys/kernel/debug/qcom_stats/cxsd` increments across a suspend.
- Lid switch:
  - gpio-keys `switch-lid` (TLMM gpio2 via PDC) spuriously wakes from CX collapse, so wakeup is disabled (`input/90-no-lid-wake.rules`; needs `ACTION=="add|bind"`).
  - Closing the lid raises no IRQ on the falling edge, so lid-close suspend doesn't work. This is a kernel issue.
- Unexplained ~5 h wakes from suspend. Next step: `echo 1 > /sys/power/pm_debug_messages`, then look for `PM: Triggering wakeup from IRQ N`.

## Known kernel/userspace bugs
- Reloading ath12k (`modprobe -r ath12k_wifi7 ath12k; modprobe ath12k_wifi7`) oopses on 7.3.4 in `mhi_queue` ← `qcom_mhi_qrtr_send` (QMI work after unload). Reboot instead.
- Plasma: suspending with the lock screen up logs `pam_unix(kde:auth): conversation failed`, and the lock screen then applies its wrong-password delay.
- Benign log noise: `i2c_hid_of 0-0016` resume error −6, a PCIe4 L2 timeout, `qcom-apm CMD timeout`, ASoC "no matching ACPI device found".

## Video decode (iris)
- Fedora's packaged DTB has `video-codec@aa00000` (`qcom,x1p42100-iris`) set to `status = "disabled"`. The node is otherwise identical to harrisonvanderbyl's DTB, which enables it with `firmware-name = "qcom/x1p42100/Microsoft/Surface12/qcvss8380_pa.mbn"`.
- Loading a patched DTB from GRUB doesn't work: systemd-stub (262.1) in `kernel-uki-dtbloader` replaces the GRUB-provided DT with its `.dtbauto` match (tested: still `disabled`).
- So `boot/96-surface-uki.install` extracts `.linux` from Fedora's UKI and runs `ukify`. It adds the patched DTB as a fixed `.dtb` and keeps Fedora's kernel SBAT line. It's unsigned. The result goes in `/boot/vmlinuz-<ver>-surface.efi`, with a `<machine-id>-<ver>-surface.conf` entry copied from Fedora's.
- The plugin runs after 95-set-boot-entry, so the newest kernel's Surface entry becomes the GRUB default.
- The initrd and cmdline still come from GRUB, as with Fedora's UKI.

## Status on Fedora (2026-11-25, after reboot)
- Working: boot from the Surface UKI (patched DTB), schedutil cpufreq, GPU acceleration (Adreno X1-45, GL accelerated), ADSP/CDSP, sound card and speakers (WSA884x), speaker boost (a smart filter in front of the speaker sink), Wi-Fi via `board.bin`, lid wakeup disabled, type cover at the LUKS prompt.
- Iris works when booted from the Surface UKI: `/dev/video0` and `/dev/video1` exist, and GStreamer v4l2h264enc → v4l2h264dec round-trips 720p correctly (300 frames decoded in about 0.6 s). It also offers H.265, VP9 and AV1 decoders.
- Not verified: suspend/CX collapse with `fw_devlink.sync_state=timeout` (`/sys/kernel/debug/qcom_stats/cxsd` across a suspend).
