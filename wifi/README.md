# wifi

`fixwifi.sh` (run by `make install`) extracts the `17cb:3378` board entry from linux-firmware's ath12k `board-2.bin` and writes it as `board.bin` next to it. ath12k loads `board.bin` before `board-2.bin`, so this unit's Wi-Fi gets board data it otherwise lacks. Reboot afterwards to load it.

## Notes
- The Wi-Fi is a WCN7850 on ath12k, PCI `17cb:1107`.
- Fedora's kernel reports its subsystem as `00ab:1414`; the Ubuntu-era notes said `17cb:3378`. `board-2.bin` has neither, and the `17cb:3378` board works.
- The script reads `board-2.bin` plain, `.xz` or `.zst`, so it works across distros.
- Reloading ath12k (`modprobe -r ath12k_wifi7 ath12k; modprobe ath12k_wifi7`) oopses on 7.3.4 in `mhi_queue` ← `qcom_mhi_qrtr_send` (QMI work after unload). Reboot instead.
- Benign: a PCIe4 (Wi-Fi bus) "Timeout waiting for L2 entry" when suspending.
- NetworkManager starts Wi-Fi auto-activation ~15 s after it starts. That doesn't block login now that `iscsi.service` is masked (see `boot/`).
