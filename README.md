# Surface Pro 12in

These are based on the Ubuntu 26.10 Concept images. This repo is a bit of a mess so far; I am probably going to move over to Fedora once it gets to a 7.3+ kernel (as there are some fixes in that kernel this device needs)

`sudo make install` will install everything here.

To get the machine booting in the first place, you need the device tree, which I have a copy of in here, sourced from harrisonvanderbyl's `surface-pro-12-inch-linux` repo. (For a live USB that doesn't have it already, that means some GRUB editing before USB boot, and chrooting into the fresh system to install it before its first boot)


| Dir | Fix |
|---|---|
| `boot/` | Device tree (needed if your distro does not bundle it) |
| `cpufreq/` | Autoload `scmi-cpufreq` (no modalias); `schedutil` default. |
| `pm/` | Strip `clk_ignore_unused pd_ignore_unused`, `fw_devlink.sync_state=timeout` so icc/gcc/gpucc sync_state isn't blocked by `1dfa000.crypto` (no `CONFIG_CRYPTO_DEV_QCE`) and `3d6a000.gmu`, enables CXPC/DDR SR in suspend. |
| `input/` | Disable `gpio-keys` wakeup (spurious `switch-lid` IRQ aborts suspend once CXPC works) - wake via power key. |
| `luks/` | Ensure the SAM/HID modules are in the initrd for LUKS unlocking |
| `firmware/` | Extracts DSP firmware from a non-BitLocker windows partition |
| `wifi/` | Fixes the `17cb:3378` entry in `ath12k`'s `board-2.bin` |
| `audio/` | Adds a custom compressor and volume gain to get a bit more sound out of the speakers  |
