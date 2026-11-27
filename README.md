# Surface Pro 12"

This contains my notes and scripts for getting the Surface Pro 12" (1st gen) working under Fedora (45). 

`sudo make install` installs all the system-wide stuff, and `make user` (no sudo) installs the speaker filter. 

Each directory contains a much longer README with all the details and technical notes about findings (yes, a bunch of that is LLM-sourced, but hey, you at least get this nice human-written top file).

If you want to install from a Fedora 45 USB image, you'll need to manually copy the device tree in `boot/dtb` to the USB stick and pass it with the `devicetree (hd0,...)/dtb` command in the GRUB command list on first boot, as the 7.2 kernel in that image doesn't have a device tree for this machine. 7.3 and up do, so I presume the Fedora 46 USB image and up will be fine.

- `boot/` builds a Surface UKI per kernel with a patched device tree (video decode, lid switch), and sets the kernel args that make suspend and boot work properly.
- `cpufreq/` autoloads the cpufreq driver for better power usage.
- `firmware/` installs the non-redistributable Windows DSP/GPU firmware.
- `wifi/` gives ath12k a `board.bin` for this unit's Wi-Fi module.
- `input/` makes the type cover's Fn key a keyboard key instead of a mouse button.
- `luks/` ensures the type cover works at the LUKS passphrase prompt.
- `plymouth/` keeps the boot splash and LUKS prompt sharp at 1x scale.
- `audio/` adds a PipeWire compressor and gain stage to get more out of the speakers.
