# Surface Pro 12"

Setup for Fedora 45 (KDE, aarch64, kernel 7.3+) on the Surface Pro 12in (X1P42100). It was originally written for the Ubuntu 26.10 Concept images; see `NOTES.md` for hardware details and open issues.

`sudo make install` installs everything system-wide; `make user` (no sudo, needs `dnf install ladspa-swh-plugins`) installs the speaker filter. Reboot afterwards.

DSP firmware comes from `firmware/surface12-firmware.zip`. It's an AES zip, so it needs `7z` (`dnf install 7zip`), and it prompts for the password.

To boot in the first place you need the device tree. Fedora 7.3+ kernels ship it as `qcom/x1p42100-microsoft-sp12in.dtb`, and the UKI embeds it for auto-selection. Fedora 7.2 doesn't have it, and auto-selection didn't work there, so `boot/dtb` is a copy (from harrisonvanderbyl's `surface-pro-12-inch-linux` repo) you can use with a `devicetree` line at the GRUB prompt on a live USB.

Secure Boot doesn't work yet (see `NOTES.md`); leave it off.

| Dir | Fix |
|---|---|
| `boot/` | A kernel-install plugin builds a UKI per kernel, with Fedora's DTB patched to enable iris video decode and to poll the lid switch (its close IRQ never fires; the IRQ is kept as a wake-on-open source), and a default "(Surface)" GRUB entry for it; Fedora's stock entries remain as a fallback. Also adds `fw_devlink.sync_state=timeout` (via `/etc/default/grub` and `grubby`) so CX/DDR collapse in suspend. Needs `dnf install dtc systemd-ukify systemd-boot-unsigned`. |
| `cpufreq/` | Autoloads `scmi-cpufreq` (no modalias). Fedora's default governor is already `schedutil`. |
| `input/` | Remaps type cover Fn from `BTN_0` (which libinput treats as a held mouse button, breaking clicks) to `KEY_FN` |
| `luks/` | Forces the SAM/HID modules into Fedora's hostonly initrd so the type cover works at the LUKS prompt |
| `firmware/` | Installs the Windows ADSP/CDSP/GPU-zap firmware (from the zip, or `extract-windows.sh` from a non-BitLocker Windows partition) and puts it and the GPU firmware in the initrd |
| `wifi/` | Extracts the `17cb:3378` entry from `ath12k`'s `board-2.bin` as `board.bin`, since there's no entry for this unit's subsystem ID |
| `plymouth/` | Sets Plymouth's `DeviceScale=1`; its automatic 2x upscales the splash/LUKS-prompt bitmaps, which looks blurry |
| `audio/` | Adds a custom compressor and volume gain to get a bit more sound out of the speakers |
