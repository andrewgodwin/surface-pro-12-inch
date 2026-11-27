# firmware

The ADSP (audio), CDSP, GPU zap shader and iris firmware for this machine is signed for it and not redistributable, so it comes from Windows. `make firmware` (run by `make install` when the firmware is missing) unpacks `surface12-firmware.zip` into `/usr/lib/firmware/qcom/x1p42100/Microsoft/Surface12`. It's an AES zip, so it needs `7z` (`dnf install 7zip`), which prompts for the password. Alternatively, `extract-windows.sh [/dev/sda3]` copies it from the Windows DriverStore on a non-BitLocker Windows partition (then run `sudo make initrd`).

`dracut.conf` puts this firmware and the Adreno GPU firmware into the initrd.

## Notes
- SoC: X1P42100 (Purwa), with an Adreno X1-45 GPU (`gen71500`), driven by msm/freedreno/turnip.
- Verified on Fedora 2026-11-25: GPU acceleration (GL, accelerated), and the ADSP and CDSP running (`/sys/class/remoteproc`). That gives sound through the WSA884x speakers, and iris decode.
- The msm GPU driver and the ADSP/CDSP remoteprocs load from the initramfs, so without their firmware in the initrd they fail with `-ENOENT` before the root fs is mounted.
- `dracut.conf` uses globs, so it matches whatever compression the distro uses (Fedora's firmware is `.xz`). Fedora builds hostonly initrds, so firmware has to be listed explicitly.
- `firmware/extract-windows.sh` defaults to `sda3`, the Windows partition; storage is UFS (`ufs_qcom`), which shows up as `sda`.
- Benign: `qcom_q6v5_pas 32300000.remoteproc: timeout waiting for subsystem event response` about 11 s into the initrd (the CDSP, in parallel; it comes up fine).
