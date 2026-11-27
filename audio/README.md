# audio

`60-surface-speaker-boost.conf` is a PipeWire filter-chain that puts a compressor and make-up gain in front of the speakers. It's installed per user with `make user` (no sudo), and needs `dnf install ladspa-swh-plugins`.

## Notes
- The speakers are 2× WSA8845, on SoundWire `swr0` and the WSA macro. The kernel caps PA and WSA RX digital volume at 0 dB, and VI sense is off, so there's no speaker protection.
  - Don't raise the kernel caps.
- The chain is sc4 at −18 dB 2:1 with +9 dB make-up gain, then a lookahead limiter at −1 dBFS.
- It's a WirePlumber 0.5 smart filter (`filter.smart`, targeting the speaker sink), so it's inserted in front of the speakers automatically. Priority-based setups don't make a filter the default sink.
  - Don't add `node.dont-reconnect`.
- Benign log noise: `qcom-apm CMD timeout`, and ASoC "no matching ACPI device found".
