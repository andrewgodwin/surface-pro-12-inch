#!/bin/sh
# Offline ath12k board.bin for Surface Pro 12in (WCN7850). linux-firmware's
# board-2.bin has no entry for our subsystem (00ab:1414 on Fedora's kernel,
# 17cb:1107 seen before); the 17cb:3378 one works.
# ath12k loads board.bin before board-2.bin. Run by `make install`.
set -eu
D=${DESTDIR:-}/usr/lib/firmware/ath12k/WCN7850/hw2.0
SRC=/usr/lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin
NAME='bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=3378,qmi-chip-id=2,qmi-board-id=255'
mkdir -p "$D"
{ if [ -f "$SRC" ]; then cat "$SRC"; elif [ -f "$SRC.xz" ]; then xz -dc "$SRC.xz"; else zstd -dc "$SRC.zst"; fi; } | python3 -I -c '
import sys, struct
name, out = sys.argv[1].encode(), sys.argv[2]
b = sys.stdin.buffer.read()
magic = b"QCA-ATH12K-BOARD\0"
assert b.startswith(magic)
pad = lambda n: (n + 3) & ~3
def ies(buf, off, end):
    while off + 8 <= end:
        i, n = struct.unpack_from("<ii", buf, off)
        yield i, buf[off + 8:off + 8 + n]
        off += 8 + pad(n)
for i, ie in ies(b, pad(len(magic)), len(b)):
    if i != 0: continue                       # BOARD IE
    sub = list(ies(ie, 0, len(ie)))
    if (0, name) in sub:                      # BOARD_NAME
        open(out, "wb").write(next(d for j, d in sub if j == 1))  # BOARD_DATA
        sys.exit(0)
sys.exit("board name not found")
' "$NAME" "$D/board.bin"
chmod 644 "$D/board.bin"
echo "$D/board.bin; reboot to load it (reloading ath12k oopses in qrtr_mhi on 7.3)"
