#!/bin/bash
echo "=== Sysbench for 16GB SSD ==="

umount /mnt/femu 2>/dev/null; mkfs.f2fs -f /dev/nvme0n1; mount -t f2fs /dev/nvme0n1 /mnt/femu
echo 1 > /sys/kernel/debug/tracing/events/f2fs/f2fs_gc_begin/enable
echo 1 > /sys/kernel/debug/tracing/events/f2fs/f2fs_gc_end/enable
echo 1 > /sys/kernel/debug/tracing/tracing_on
echo > /sys/kernel/debug/tracing/trace
cat /sys/block/nvme0n1/stat > /tmp/stat_before.txt

TEST_DIR="/mnt/femu/test_files"
mkdir -p $TEST_DIR
cd $TEST_DIR

# Smaller for 16GB: Use 8GB total (50% of SSD)
TEST_FILE_SIZE="8G"
FILE_NUM=8           # 8 files × 1GB each
BLOCK_SIZE="1K"
THREADS=2

echo "1. Prepare 8GB..."
sysbench fileio \
    --file-total-size=$TEST_FILE_SIZE \
    --file-num=$FILE_NUM \
    --file-block-size=$BLOCK_SIZE \
    prepare

echo "2. Random writes (3 rounds)..."
for round in {1..3}; do
    echo "  Round $round/3 (500k ops)..."
    sysbench fileio \
        --file-total-size=$TEST_FILE_SIZE \
        --file-num=$FILE_NUM \
        --file-test-mode=rndwr \
        --file-block-size=$BLOCK_SIZE \
        --file-io-mode=sync \
        --time=0 \
        --events=500000 \
        --threads=$THREADS \
        run 2>&1 | grep -E "written:|Total transferred"
done

echo "3. Mixed ops..."
sysbench fileio \
    --file-total-size=$TEST_FILE_SIZE \
    --file-num=$FILE_NUM \
    --file-test-mode=rndrw \
    --file-rw-ratio=1 \
    --file-block-size=$BLOCK_SIZE \
    --time=0 \
    --events=1000000 \
    --threads=$THREADS \
    run 2>&1 | grep -E "read:|written:|Total transferred"

cat /sys/kernel/debug/tracing/trace > /tmp/gc_trace.txt
cat /sys/block/nvme0n1/stat > /tmp/stat_after.txt
sync

echo "4. Cleanup..."
sysbench fileio cleanup

echo ""
echo "=== RESULTS ==="
GC_COUNT=$(grep -c "f2fs_gc_begin" /tmp/gc_trace.txt)
echo "GC cycles: $GC_COUNT"

BEFORE=$(awk '{print $7}' /tmp/stat_before.txt)
AFTER=$(awk '{print $7}' /tmp/stat_after.txt)
LOGICAL=$(( 8*1024*1024*1024 + 3*500000*1024 + 1000000*1024 ))  # 8GB + 1.5GB + 1GB
DELTA=$((AFTER - BEFORE))
PHYSICAL=$((DELTA * 512))
WAF=$(echo "scale=3; $PHYSICAL / $LOGICAL" | bc 2>/dev/null || echo "N/A")
echo "WAF: $WAF"
echo "Physical: $(($PHYSICAL/1024/1024/1024)) GB, Logical: $(($LOGICAL/1024/1024/1024)) GB"