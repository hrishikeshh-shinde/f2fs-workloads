#!/bin/bash
# 1. Setup
umount /mnt/femu 2>/dev/null; mkfs.f2fs -f /dev/nvme0n1; mount -t f2fs /dev/nvme0n1 /mnt/femu

# 2. Enable GC trace
echo 1 > /sys/kernel/debug/tracing/events/f2fs/f2fs_gc_begin/enable
echo 1 > /sys/kernel/debug/tracing/events/f2fs/f2fs_gc_end/enable
echo 1 > /sys/kernel/debug/tracing/tracing_on
echo > /sys/kernel/debug/tracing/trace

# 3. Initial stats
cat /sys/block/nvme0n1/stat > /tmp/stat_before.txt

# 4. Workload (trigger GC)
cd /root/rocksdb
rm -rf /mnt/femu/rdb
# Fill 10GB (75%)
./db_bench --db=/mnt/femu/rdb --benchmarks=fillrandom --num=10000000 --value_size=1024 --threads=2
# Update 1M keys 3x
for i in {1..3}; do
  ./db_bench --db=/mnt/femu/rdb --benchmarks=updaterandom --num=1000000 --use_existing_db=1 --threads=2
done
# Delete 2M
./db_bench --db=/mnt/femu/rdb --benchmarks=deleterandom --num=2000000 --use_existing_db=1

# 5. Final stats
cat /sys/block/nvme0n1/stat > /tmp/stat_after.txt
sync

# 6. Verify GC
GC_COUNT=$(grep -c "f2fs_gc_begin" /sys/kernel/debug/tracing/trace)
echo "GC cycles: $GC_COUNT"
if [ $GC_COUNT -eq 0 ]; then
  echo "Adding emergency writes..."
  ./db_bench --db=/mnt/femu/rdb --benchmarks=overwrite --num=2000000 --use_existing_db=1
fi

# 7. Calculate
LOGICAL=$(( (10000000 + 3*1000000) * 1024 )) # Fill + updates
echo $LOGICAL > /tmp/logical.txt
echo "Logical: $(($LOGICAL/1024/1024/1024)) GB"
