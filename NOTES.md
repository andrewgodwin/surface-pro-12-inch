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
  - On Fedora, `fw_devlink.sync_state=timeout` alone did nothing. Fedora's kernel has `driver_deferred_probe_timeout = -1` (read from `/proc/kcore`), so the timeout never fires. There was no "Forcing sync_state()" message, and `state_synced` stayed 0 on gcc, gpucc, `1700000.interconnect` and `interconnect-1`.
  - The interconnect summary showed INT_MAX votes, and a suspend (2026-11-25) left cxsd/ddr/aosd counts at 0. Hence `deferred_probe_timeout=30`.
  - Verified 2026-11-25: all four providers get "Timed out. Forcing sync_state()" at ~51 s and `state_synced` = 1, with no INT_MAX votes left and nothing broken. A 67 s suspend then gave cxsd/ddr 686 entries, ~62 s in DDR collapse (19.2 MHz ticks), with aosd counting too.
- RTC (`rtc-pm8xxx`) has no `wakealarm`, so `rtcwake` can't be used for suspend tests; wake with the power button.
- Lid switch:
  - On Ubuntu, gpio-keys `switch-lid` (TLMM gpio2 via PDC) seemed to spuriously wake from CX collapse, so wakeup was disabled with a udev rule. That rule is gone now (see below); the spurious wakes were probably the ~5 h firmware wakes.
  - Closing the lid raises no IRQ on the falling edge, so lid-close suspend didn't work. This is a kernel issue, worked around below.
  - Confirmed on Fedora 7.3 (2026-11-25) by sampling `/sys/kernel/debug/gpio`. The TLMM gpio2 level does follow the lid (high = open, low = closed). Closing the lid leaves IRQ 127 unchanged; opening it increments it. So the sensor works, and only the falling edge of the dual-edge IRQ (via PDC) is lost. gpio-keys only re-reads the pin on the rising edge, which reads as "open", so it never reports a close.
  - Workaround (`96-surface-uki.install`): `switch-lid` is copied into a `gpio-keys-polled` node (`/gpio-keys-lid`, 200 ms poll) for the lid state.
  - With `LID_WAKE=1`, the IRQ `switch-lid` stays in `gpio-keys` as a wake source only, as `EV_KEY`/`KEY_RESERVED`, which the input core drops. Upstream DT gives it `wakeup-event-action = EV_ACT_DEASSERTED`, so only lid open wakes, and that edge works. It mustn't stay SW_LID: it never reports closed, and `upowerd` (so KDE) watches only one lid device. It picked that one, and lid-close suspend broke.
  - Verified overnight 2026-11-26: lid close → suspend, lid open → `Triggering wakeup from IRQ 173` (msmgpio 2). The lid IRQ fired once all night. If wake-on-open ever misbehaves, set `LID_WAKE=0` and run `sudo sh boot/setup-boot.sh install`.
  - Gotcha: `/etc/udev/rules.d` is baked into the hostonly initrd, so removing a rule needs `dracut -f`.
- Unexplained ~5 h wakes from suspend. On 2026-11-26 it woke after 18424 s with `pm_debug_messages` on: "Checking wakeup interrupts" but no `Triggering wakeup from IRQ`, so no Linux wake IRQ was pending. It's firmware or a timer below Linux, not the lid. KDE re-suspends 10 s later if the lid is still closed. `/etc/tmpfiles.d/surface-pm-debug.conf` (not in the repo) keeps `pm_debug_messages` on to catch more.

## Boot splash
- Plymouth draws on msm (not simpledrm, because of `UseSimpledrmNoLuks` with LUKS) at the native 2196x1464, and auto-picks scale 2, i.e. a 1098x732 logical canvas. Text is rendered at full resolution, but the spinner theme's bitmaps (watermark 149x43, 32x32 spinner, entry box) are upscaled, which looks blurry. There's no BGRT logo on this device.
- Scale is integer-only, so `plymouth/plymouthd.conf` sets `DeviceScale=1`: sharp but small. A theme copy with larger fonts would help the text only. To debug: `plymouth.debug` on the cmdline, then read `/var/log/plymouth-debug.log`.

## Boot time
- 2026-11-25, before fixes: 1 s kernel + 46 s initrd + 63 s userspace = 1 min 50 s.
  - The firmware advertises a TPM2, but there's no Linux TPM device ("ima: No TPM chip found"). systemd waits for `/dev/tpm0` and `/dev/tpmrm0` until the job timeout, in the initrd (~33 s after LUKS unlock) and again after switch-root (~45 s). Fix: `systemd.tpm2_wait=0` (also on Fedora's Snapdragon wiki page).
  - iscsi-initiator-utils' NM dispatcher script `04-iscsi` runs `systemctl --no-block reload iscsi.service` on any interface up. That reload job is ordered after `network-online.target`, and `remote-fs.target` after `iscsi.service`, so `systemd-user-sessions` and the login screen waited ~16 s for Wi-Fi. Fix: mask `iscsi.service` (Makefile `MASK`).
- Still left: NetworkManager starts Wi-Fi auto-activation about 15 s after it starts (no longer blocks login); `qcom_q6v5_pas 32300000.remoteproc: timeout waiting for subsystem event response` at about 11 s in the initrd (CDSP, in parallel).

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
- Working: boot from the Surface UKI (patched DTB), schedutil cpufreq, GPU acceleration (Adreno X1-45, GL accelerated), ADSP/CDSP, sound card and speakers (WSA884x), speaker boost (a smart filter in front of the speaker sink), Wi-Fi via `board.bin`, lid-close suspend and lid-open wake, type cover at the LUKS prompt.
- Iris works when booted from the Surface UKI: `/dev/video0` and `/dev/video1` exist, and GStreamer v4l2h264enc → v4l2h264dec round-trips 720p correctly (300 frames decoded in about 0.6 s). It also offers H.265, VP9 and AV1 decoders.
- Suspend: CX/DDR collapse works with `fw_devlink.sync_state=timeout deferred_probe_timeout=30`. Wake on the power button works (IRQ 193, `pmic_pwrkey`). The `i2c_hid_of 0-0016` resume error -6 is benign.
