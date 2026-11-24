# Surface Pro 12"

These are based on the Ubuntu 26.10 Concept images. This repo is a bit of a mess so far; I am probably going to move over to Fedora once it gets to a 7.3+ kernel (as there are some fixes in that kernel this device needs)

`sudo make install` will install everything here.

To get the machine booting in the first place, you need the device tree, which I have a copy of in here, sourced from harrisonvanderbyl's `surface-pro-12-inch-linux` repo. (For a live USB that doesn't have it already, that means some GRUB editing before USB boot, and chrooting into the fresh system to install it before its first boot)

There was a bunch of kernel args and defaults in the Ubuntu X1E Concept images that I just didn't seem to need as well; further testing might be needed to verify that.

| Dir | Fix |
|---|---|
| `boot/` | Device tree (needed if your distro does not bundle it) |
| `cpufreq/` | Autoload `scmi-cpufreq` (no modalias); `schedutil` default. |
| `pm/` | Removes some default args that aren't needed and fixes up some other power management |
| `input/` | Disables `gpio-keys` wakeup (the lid switch goes off randomly), making it only the power key |
| `luks/` | Ensure the SAM/HID modules are in the initrd for LUKS unlocking |
| `firmware/` | Extracts DSP firmware from a non-BitLocker windows partition |
| `wifi/` | Fixes the `17cb:3378` entry in `ath12k`'s `board-2.bin` |
| `audio/` | Adds a custom compressor and volume gain to get a bit more sound out of the speakers  |
