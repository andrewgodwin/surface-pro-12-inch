#!/bin/sh
# Copy Surface Pro 12in ADSP/CDSP/GPU-zap firmware from the Windows DriverStore.
# Usage: sudo firmware/extract-windows.sh [/dev/sda3]   (then: sudo make initrd)
set -eu
DEV=${1:-/dev/sda3}
D=${DESTDIR:-}/usr/lib/firmware/qcom/x1p42100/Microsoft/Surface12
M=$(mktemp -d)
trap 'umount "$M" 2>/dev/null; rmdir "$M"' EXIT
mount -o ro -t ntfs3 "$DEV" "$M"
R=$M/Windows/System32/DriverStore/FileRepository

# newest matching driver package dir
pkg() { ls -dt "$R"/$1.inf_arm64_*/ | head -1 | sed 's:/$::'; }

mkdir -p "$D"
take() { p=$(pkg "$1"); shift; for f; do install -m644 "$p/$f" "$D/"; echo "$D/$f  <- ${p##*/}"; done; }
take surfacepro_ext_adsp8380 qcadsp8380.mbn adsp_dtbs.elf adspr.jsn adsps.jsn adspua.jsn battmgr.jsn
take qcnspmcdm_ext_cdsp8380  qccdsp8380.mbn cdsp_dtbs.elf cdspr.jsn
take qcdx8380                qcdxkmsucpurwa.mbn qcvss8380_pa.mbn
