#!/bin/bash
umount /mnt/femu 2>/dev/null; mkfs.f2fs -f /dev/nvme0n1; mount -t f2fs /dev/nvme0n1 /mnt/femu
echo 1 > /sys/kernel/debug/tracing/events/f2fs/f2fs_gc_begin/enable
echo 1 > /sys/kernel/debug/tracing/events/f2fs/f2fs_gc_end/enable
echo 1 > /sys/kernel/debug/tracing/tracing_on
echo > /sys/kernel/debug/tracing/trace
cat /sys/block/nvme0n1/stat > /tmp/stat_before.txt

LEVELDB_BENCH=$(find /root/leveldb -name "db_bench" -type f | head -1)
rm -rf /mnt/femu/ldb

# Fill
$LEVELDB_BENCH --db=/mnt/femu/ldb --benchmarks=fillrandom --num=10000000 --value_size=1024 --threads=2

# Updates (FIXED FLAG)
for i in {1..3}; do
  $LEVELDB_BENCH --db=/mnt/femu/ldb --benchmarks=overwrite --num=1000000 --use_existing_db=1 --threads=2
done

# Delete
$LEVELDB_BENCH --db=/mnt/femu/ldb --benchmarks=deleterandom --num=2000000 --use_existing_db=1

cat /sys/block/nvme0n1/stat > /tmp/stat_after.txt
sync

GC_COUNT=$(grep -c "f2fs_gc_begin" /sys/kernel/debug/tracing/trace)
echo "GC cycles: $GC_COUNT"
if [ $GC_COUNT -eq 0 ]; then
  echo "Adding emergency writes..."
  $LEVELDB_BENCH --db=/mnt/femu/ldb --benchmarks=overwrite --num=2000000 --use_existing_db=1
fi

LOGICAL=$(( (10000000 + 3*1000000) * 1024 ))
echo $LOGICAL > /tmp/logical.txt
echo "Logical: $(($LOGICAL/1024/1024/1024)) GB"