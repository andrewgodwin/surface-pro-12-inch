# Surface Pro 12in (X1P42100) fixes — Ubuntu 26.10, linux-qcom-x1e 7.3

`sudo make install` · `sudo make uninstall` · `make install DESTDIR=/tmp/x` (stage only) · `make user` (per-user, no sudo; needs `swh-plugins`)

| Dir | Fix |
|---|---|
| `cpufreq/` | Autoload `scmi-cpufreq` (no modalias); `schedutil` default. |
| `pm/` | Strip `clk_ignore_unused pd_ignore_unused`; `fw_devlink.sync_state=timeout` so icc/gcc/gpucc sync_state isn't blocked by `1dfa000.crypto` (no `CONFIG_CRYPTO_DEV_QCE`) and `3d6a000.gmu`. Enables CXPC/DDR SR in suspend. |
| `input/` | Disable `gpio-keys` wakeup: spurious `switch-lid` IRQ aborts suspend once CXPC works. Wake via power key. |
| `luks/` | Root is LUKS2 on `sda5`, `/boot` on `sda6`. dracut `crypt`; pin SAM/HID chain so the cover works at the prompt; `rd.luks.name`/`options` from `/etc/crypttab` (non-hostonly initrd doesn't embed it). |
| `firmware/` | ADSP/CDSP/zap firmware isn't redistributable: `sudo firmware/extract-windows.sh [/dev/sda3]` copies it from the Windows DriverStore (newest `surfacepro_ext_adsp8380`, `qcnspmcdm_ext_cdsp8380`, `qcdx8380` pkgs) to `qcom/x1p42100/Microsoft/Surface12/`, then `sudo make initrd`. `dracut.conf` puts it and `gen71500_*` in the initrd, otherwise they fail with `-ENOENT` before root mounts. |
| `audio/` | Speakers work but kernel caps PA and WSA RX digital volume at 0 dB (no VI-sense protection). `make user`: PipeWire filter-chain sink `surface_speaker_boost` (sc4 −18 dB/2:1, +9 dB makeup → lookahead limiter −1 dBFS) as default over the raw sink. Measured +9.0 dB below threshold, 0 dBFS sine → −1.0 dBFS peak. |

GRUB params are appended idempotently from `/etc/default/grub.d/zz-surface-*.cfg`; `/etc/default/grub` is untouched.

Verify: `/sys/devices/system/cpu/cpufreq/policy*`, `grep -c 2147483647 /sys/kernel/debug/interconnect/interconnect_summary` (0), `/sys/kernel/debug/qcom_stats/cxsd` after suspend.

Applied earlier from `~/surface-pro-12-inch-linux` (not managed here):
- `boot/dtb` → `/boot/dtb` (identical); loaded via GRUB `devicetree`.
- `fixwifi.sh` (local copy of bdencoder): `ath12k/WCN7850/hw2.0/board.bin` = `subsystem-device=3378` entry from `board-2.bin`.
- `installaudio.sh`: audioreach topology built → `qcom/x1e80100/X1P42100-Microsoft-Surface-Pro-12in-tplg.bin` (uncompressed, shadows packaged `.zst`). UCM step was a no-op (`alsa-ucm-conf` 1.2.16.1, no divert).
- Repo's `lib/firmware` not used: `gen71500_*` are packaged; `Surface12/` came from Windows (below).
- `installsensors.sh`, partial: `usr/` copied (all match), `61-sensor-surface-pro-12.rules`, `hexagonrpcd` in `/usr/local` + `hexagonrpc.service` (disabled). SSC `iio-sensor-proxy` build failed (`libssc` missing) → stock deb, not held; no rotation/ALS.
- `wireupcameras.sh`: not persisted (manual `media-ctl`, lost on reboot).

Known open: `i2c_hid_of 0-0016` resume `-6` (benign); PCIe4 `Timeout waiting for L2 entry`.
