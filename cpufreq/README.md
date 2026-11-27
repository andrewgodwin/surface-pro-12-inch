# cpufreq

`scmi-cpufreq.conf` goes into `/etc/modules-load.d` so `scmi-cpufreq` loads at boot. Fedora's default governor is already `schedutil`, so nothing else is needed.

## Notes
- `scmi-cpufreq` has no modalias: the SCMI perf protocol (0x13) device only appears once the driver registers, so udev never autoloads it.
- Without it there are no cpufreq policies, and idle draw is about 1 W higher.
