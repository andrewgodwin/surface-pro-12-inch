# plymouth

`plymouthd.conf` goes in `/etc/plymouth` and sets `DeviceScale=1`, so the boot splash and LUKS prompt are drawn 1:1. They're sharp, if a little small. `make install` rebuilds the initrd so it takes effect.

## Notes
- Plymouth draws on msm, at the native 2196x1464. It doesn't use simpledrm, because Fedora sets `UseSimpledrmNoLuks` and this machine uses LUKS.
- Plymouth auto-picks scale 2, which gives a 1098x732 logical canvas:
  - text is still rendered at full resolution;
  - the spinner theme's bitmaps are upscaled 2x and look blurry: the 149x43 watermark, the 32x32 spinner and the entry box.
  - There's no BGRT logo on this device.
- Plymouth's scale is integer-only, so 1.5x isn't possible. A theme copy with larger fonts would only help the text.
- GRUB and the firmware framebuffer were already at the native resolution; it's only Plymouth's scaling. To debug, add `plymouth.debug` to the cmdline, then read `/var/log/plymouth-debug.log`.
