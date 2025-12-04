#!/bin/bash
# Original working FEMU command
QEMU_BIN=/users/hri20shi/FEMU/build-femu/qemu-system-x86_64

# Clean old stats
rm -f /users/hri20shi/femu_stats.csv 2>/dev/null

echo "Starting FEMU (16GB SSD)..."
echo "Connect with: ssh -p 8080 user@localhost"
echo "Stats will be saved to: /users/hri20shi/femu_stats.csv"
echo ""
echo "Press Ctrl+A C then type 'quit' to stop FEMU"
echo ""

sudo $QEMU_BIN \
    -name "FEMU-VM" \
    -enable-kvm \
    -cpu host \
    -smp 8 \
    -m 16G \
    -device femu,devsz_mb=16384,femu_mode=1 \
    -drive file=/users/hri20shi/femu.qcow2,format=qcow2,if=virtio \
    -drive file=/users/hri20shi/seed.img,format=raw,if=virtio \
    -net user,hostfwd=tcp::8080-:22 -net nic \
    -nographic
