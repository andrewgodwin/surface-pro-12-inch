# boot

`setup-boot.sh` (run by `make install`) does three things:

- It installs `96-surface-uki.install` as a kernel-install plugin and runs it for every installed kernel. For each kernel the plugin:
  - builds `/boot/vmlinuz-<ver>-surface.efi`, a UKI with Fedora's SP12 device tree patched:
    - iris video decode is enabled;
    - the lid switch is polled;
    - the lid's wake interrupt is kept, so opening the lid wakes the machine;
  - adds a "(Surface)" GRUB entry for it and makes that the default. Fedora's stock entries stay untouched as the fallback;
  - prunes other boards' DTBs from `/boot/dtb-<ver>`, because `/boot` is only 1 GB.
- It adds kernel args, in both `GRUB_CMDLINE_LINUX` and every BLS entry:
  - `fw_devlink.sync_state=timeout deferred_probe_timeout=30`, so suspend reaches CX/DDR collapse;
  - `systemd.tpm2_wait=0`, which saves ~80 s of boot.
- It cleans up what earlier versions of this repo installed.

`dracut-no-rescue.conf` turns off Fedora's rescue image. The Makefile also masks `iscsi.service`, which held up the login screen until Wi-Fi connected.

Needs `dnf install dtc systemd-ukify systemd-boot-unsigned`. Secure Boot doesn't work yet (see the notes below), so leave it off. `setup-boot.sh uninstall` reverts everything and sets the default back to Fedora's newest entry.

`dtb` is harrisonvanderbyl's DTB (from `surface-pro-12-inch-linux`). Fedora 7.2 doesn't ship one, so for booting a 7.2 live USB, load it with a `devicetree` line at the GRUB prompt. On 7.3+ it isn't needed.

## Notes

### Fedora's UKI and the device tree
- `kernel-uki-dtbloader` is a systemd-stub UKI with `.dtbauto` sections and `.hwids`. 7.3.4 includes the SP12 DTB (`qcom/x1p42100-microsoft-sp12in.dtb`, compatible `microsoft,surface-pro-12in`).
  - Auto-selection didn't work on 7.2.11, which also doesn't ship the DTB in `/boot/dtb-<ver>`.
  - On 7.3.4 the stub auto-selects the packaged DTB, and that overrides any DTB loaded by GRUB (tested with a patched DTB: iris was still `disabled`). So patching has to happen inside our own UKI.
- The plugin extracts `.linux` from Fedora's UKI, then runs `ukify` with the patched DTB as a fixed `.dtb`, keeping Fedora's kernel SBAT line. The result is unsigned.
  - The entry `<machine-id>-<ver>-surface.conf` is a copy of Fedora's, with the title, version and `linux` lines changed. The initrd and cmdline still come from GRUB, as with Fedora's UKI.
  - The plugin runs after `95-set-boot-entry`, so the newest kernel's Surface entry wins the default.
- `grub2-mkconfig` rewrites every BLS entry's options from `GRUB_CMDLINE_LINUX` whenever `/etc/default/grub` is newer than `/etc/kernel/cmdline`, so kernel args must go in both places.
- Not used and apparently not needed: `clk_ignore_unused`, `pd_ignore_unused`, `efi=noruntime`, `cma=128M`, `GRUB_BADRAM="0x8800000000,0xf800000000"`. If boot or suspend breaks, try adding them back with grubby.

### Iris (video decode)
- Fedora's DTB has `video-codec@aa00000` (`qcom,x1p42100-iris`) set to `status = "disabled"`. Otherwise the node is identical to harrisonvanderbyl's, which enables it with `firmware-name = "qcom/x1p42100/Microsoft/Surface12/qcvss8380_pa.mbn"`. The plugin sets both.
- Verified 2026-11-25: `/dev/video0` (decoder) and `/dev/video1` (encoder) exist. GStreamer `v4l2h264enc` → `v4l2h264dec` round-trips 720p correctly, decoding 300 frames in ~0.6 s. It also offers H.265, VP9 and AV1 decoders.

### Lid switch
- On Ubuntu, gpio-keys `switch-lid` (TLMM gpio2 via PDC) seemed to wake spuriously from CX collapse, so its wakeup was disabled with a udev rule. That was probably the ~5 h firmware wake (see Suspend), and the rule is gone now.
- Closing the lid raises no IRQ on the falling edge. Confirmed on 7.3 (2026-11-25) by sampling `/sys/kernel/debug/gpio`:
  - the gpio2 level follows the lid (high = open, low = closed);
  - closing leaves its IRQ count unchanged, and opening increments it;
  - so the sensor works, and only the falling edge of the dual-edge IRQ (via PDC) is lost.
  - gpio-keys only re-reads the pin on the rising edge, which reads as "open", so it never reports a close.
- Workaround: the plugin copies `switch-lid` into a `gpio-keys-polled` node (`/gpio-keys-lid`, 200 ms poll) for the lid state.
- With `LID_WAKE=1`, the IRQ `switch-lid` stays in `gpio-keys` as a wake source only, re-typed as `EV_KEY`/`KEY_RESERVED`, which the input core drops.
  - Upstream DT gives it `wakeup-event-action = EV_ACT_DEASSERTED`, so only opening the lid wakes, and that edge works.
  - It mustn't stay SW_LID. It never reports closed, and `upowerd` (and so KDE) watches only one lid device. It picked that one, and lid-close suspend broke.
- Verified overnight 2026-11-26: closing the lid suspends, and opening it wakes (`Triggering wakeup from IRQ 173`, msmgpio 2). The lid IRQ fired once all night. If wake-on-open ever misbehaves, set `LID_WAKE=0` and rerun `sudo sh boot/setup-boot.sh install`.
- Gotcha: `/etc/udev/rules.d` is baked into the hostonly initrd, so removing a rule needs `dracut -f`.

### Suspend
- icc `sync_state` is blocked by consumers that never get a driver:
  - `1dfa000.crypto`: Fedora doesn't build `CRYPTO_DEV_QCE`.
  - `3d6a000.gmu`: never bound.
  - Without the sync, interconnect votes stay pinned at INT_MAX and CX/DDR never collapse. Hence `fw_devlink.sync_state=timeout`.
- On Fedora that karg alone did nothing. Fedora's kernel has `driver_deferred_probe_timeout = -1` (read from `/proc/kcore`), so the timeout never fires:
  - there was no "Forcing sync_state()" message;
  - `state_synced` stayed 0 on gcc, gpucc, `1700000.interconnect` and `interconnect-1`;
  - a suspend left the cxsd/ddr/aosd counts at 0.
  - Hence `deferred_probe_timeout=30`. It restarts on every module load, so the 30 s count from the last one.
- Verified 2026-11-25:
  - all four providers log "Timed out. Forcing sync_state()" at ~51 s and get `state_synced` = 1;
  - no INT_MAX votes are left, and nothing broke;
  - a 67 s suspend gave cxsd/ddr 686 entries, ~62 s of it in DDR collapse (19.2 MHz ticks).
- Measured overnight 2026-11-26: ~6% (≈2 Wh) over 9 h 21 min, i.e. ~0.15–0.2 W.
- Wake on the power button works (`pmic_pwrkey`, IRQ ~193). The RTC (`rtc-pm8xxx`) has no `wakealarm`, so `rtcwake` can't be used for tests.
- Unexplained ~5 h wakes. On 2026-11-26 it woke after 18424 s with `pm_debug_messages` on. The log showed "Checking wakeup interrupts" but no `Triggering wakeup from IRQ`, so no Linux wake IRQ was pending. The cause is firmware or a timer below Linux, not the lid. KDE re-suspends 10 s later if the lid is still closed. To catch more: `echo 1 > /sys/power/pm_debug_messages` before suspending.
- Plasma: suspending with the lock screen up logs `pam_unix(kde:auth): conversation failed`, and the lock screen then applies its wrong-password delay.

### Boot time
- 2026-11-25, before fixes: 1 s kernel + 46 s initrd + 63 s userspace = 1 min 50 s.
- TPM: the firmware advertises a TPM2, but Linux has no TPM device ("ima: No TPM chip found"). systemd waits for `/dev/tpm0` and `/dev/tpmrm0` until the job timeout, both in the initrd (~33 s after LUKS unlock) and again after switch-root (~45 s). Fix: `systemd.tpm2_wait=0` (also on Fedora's Snapdragon wiki page).
- iSCSI: iscsi-initiator-utils' NetworkManager dispatcher script `04-iscsi` runs `systemctl --no-block reload iscsi.service` whenever an interface comes up.
  - That job is ordered after `network-online.target`, and `remote-fs.target` is ordered after `iscsi.service`.
  - So `systemd-user-sessions` and the login screen waited ~16 s for Wi-Fi.
  - Fix: mask `iscsi.service` (Makefile `MASK`).
- After the fixes: ~22 s. Still left: NetworkManager starts Wi-Fi auto-activation ~15 s after it starts (that no longer blocks login).

### /boot space
- `/boot` is 1 GB. Each kernel's `/boot/dtb-<ver>` holds ~1600 DTBs (110 MB).
- The plugin keeps only DTBs whose root `compatible` contains the machine's (read from `/proc/device-tree`, falling back to `microsoft,surface-pro-12in`), so it still finds a renamed file. It only prunes when it finds a match. Each kernel now takes ~125 MB.
- Rescue image: `51-dracut-rescue.install` only builds it when it's missing, from whatever kernel is being installed at that point.
  - The original was built from 7.2.11, which can't select a DTB here, and after 7.2 was removed it had no `/lib/modules` either.
  - Its generic initrd was ~300 MB.
  - So it's disabled; the stock entry is the fallback.

### Fedora's DTB vs harrisonvanderbyl's (`dtb`)
- Compared 2026-11-26 against 7.3.4's DTB, with phandles resolved. Fedora's is the newer upstream:
  - it adds CoreSight nodes, the PMIC ADC (`spmi-adc5-gen3`) and its thermistor channels, a `domain-sleep-0` system idle state with lower cluster-sleep latencies, USB interconnects, and fastrpc vmids;
  - it fixes the QMP PHY clocks;
  - `pci@` nodes are renamed `pcie@`.
- What harrisonvanderbyl's has that Fedora's lacks. Nothing here is worth porting:
  - iris enabled, which we patch;
  - a second GPU SMMU stream (`iommus` SID 1); the GPU works without it;
  - a PDC `reg` size of 0x30000 instead of 0x10000; the driver only maps 0x10000;
  - 12 extra `reserved-memory` regions. All but `xbl-tmp-buffer` are already reserved in, or absent from, the UEFI memory map (`/proc/iomem`). UEFI hands most of `xbl-tmp-buffer` to Linux as RAM, so it's bootloader scratch.
- On Ubuntu, the audio nodes were identical between the two DTBs, and the firmware paths match.

### Secure Boot (tried 2026-11-25; left off)
- With Secure Boot off, the Surface firmware reports Setup Mode with empty PK/KEK/db/dbx. The keys only appear once a mode (e.g. "Microsoft & 3rd party CA") is selected, and switching back to off doesn't clear anything.
- With "Microsoft & 3rd party CA", shim (16.1) and GRUB (2.12-83) load.
  - Then both Fedora's stock signed UKI and our MOK-signed UKI go to a black screen with a `_` cursor. That happened even with `earlycon=efifb keep_bootcon ignore_loglevel` and no `quiet`.
  - There's no journal or pstore, so the kernel likely never starts.
  - Suspect: GRUB's handoff to a UKI under Secure Boot.
- A MOK from that attempt (`CN=Surface Pro 12 UKI signing key (rattata)`) is still enrolled; its private key has been deleted. To remove it: `mokutil --export`, then `mokutil --delete` the matching `MOK-*.der`, then confirm in MokManager on reboot.
- Next idea: skip GRUB. A firmware boot entry would run shim with a MOK-signed UKI on the ESP as its second stage, with the initrd and cmdline embedded. That would also cover the initrd, which GRUB loads unverified.

### Clock
- The PMIC RTC is read-only, but the DT has `qcom,uefi-rtc-info`, so the time offset lives in the `RTCInfo` UEFI variable, which Windows uses too.
- Fedora's installer had set `LOCAL` in `/etc/adjtime` (because of the dual boot), so systemd shifted the clock by 7 h about 23 s into boot, and early log timestamps were off.
- Switched to UTC on 2026-11-26 (`timedatectl set-local-rtc 0`). Windows needs `RealTimeIsUniversal=1` (QWORD) under `HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation`.
