# luks

`dracut.conf` forces the crypt modules and the Surface Aggregator (SAM) and HID driver chain into the initrd, so the type cover works at the LUKS passphrase prompt.

## Notes
- Fedora builds hostonly initrds, which only include drivers bound at build time and leave out the SAM/HID chain the type cover needs.
- `/etc/crypttab` is baked into the initrd too, so changing it (e.g. a new LUKS UUID) needs `dracut -f --regenerate-all`, along with an updated `rd.luks.uuid=` in `GRUB_CMDLINE_LINUX` and every BLS entry.
