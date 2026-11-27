# input

`61-type-cover-fn.hwdb` remaps the type cover's Fn key from `BTN_0` to `KEY_FN`. `make install` installs it and reloads hwdb.

## Notes
- The type cover's Fn key sends HID GenericDesktop.SystemFunctionShift (`0x10097`), which hid-input maps to `BTN_0`. libinput treats that as a pointer button, so holding Fn, or a lost Fn release, makes KWin think a mouse button is held, and it swallows clicks. `KEY_FN` is a plain keyboard key.
- The lid switch is also a `gpio-keys` input, but its fix is in the device tree; see `boot/`. The udev rule that used to disable lid wakeup is gone.
- Benign: `i2c_hid_of 0-0016` logs a resume error −6 after every suspend.
