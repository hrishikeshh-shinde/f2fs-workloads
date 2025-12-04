#!/bin/bash
umount /mnt/femu 2>/dev/null; mkfs.f2fs -f /dev/nvme0n1; mount -t f2fs /dev/nvme0n1 /mnt/femu
echo 1 > /sys/kernel/debug/tracing/events/f2fs/f2fs_gc_begin/enable
echo 1 > /sys/kernel/debug/tracing/events/f2fs/f2fs_gc_end/enable
echo 1 > /sys/kernel/debug/tracing/tracing_on
echo > /sys/kernel/debug/tracing/trace
cat /sys/block/nvme0n1/stat > /tmp/stat_before.txt

DB="/mnt/femu/sqlite_wal.db"
rm -f $DB*

# Create with WAL
sqlite3 $DB "PRAGMA journal_mode=WAL;"
sqlite3 $DB "CREATE TABLE data (id INTEGER PRIMARY KEY, value BLOB);"

echo "Inserting 10M rows (batched)..."
python3 -c "
import sqlite3, os, sys
conn = sqlite3.connect('$DB')
cursor = conn.cursor()
BATCH_SIZE = 10000
for batch_start in range(1, 10000001, BATCH_SIZE):
    cursor.execute('BEGIN')
    batch_end = min(batch_start + BATCH_SIZE, 10000001)
    for i in range(batch_start, batch_end):
        cursor.execute('INSERT INTO data VALUES (?, ?)', (i, os.urandom(1024)))
    cursor.execute('COMMIT')
    if batch_start % 100000 == 0:
        sys.stdout.write('.'); sys.stdout.flush()
print()
"

echo "Updating 1M rows × 3 (batched)..."
for r in {1..3}; do
  python3 -c "
import sqlite3, random, os, sys
conn = sqlite3.connect('$DB')
cursor = conn.cursor()
BATCH_SIZE = 10000
cursor.execute('BEGIN')
for count in range(1000000):
    cursor.execute('UPDATE data SET value=? WHERE id=?', 
                  (os.urandom(1024), random.randint(1, 10000000)))
    if count % BATCH_SIZE == 0 and count > 0:
        cursor.execute('COMMIT')
        cursor.execute('BEGIN')
        sys.stdout.write('.'); sys.stdout.flush()
cursor.execute('COMMIT')
print()
  "
done

echo "Deleting 2M rows (batched)..."
python3 -c "
import sqlite3, random, sys
conn = sqlite3.connect('$DB')
cursor = conn.cursor()
BATCH_SIZE = 10000
cursor.execute('BEGIN')
for count in range(2000000):
    cursor.execute('DELETE FROM data WHERE id=?', (random.randint(1, 10000000),))
    if count % BATCH_SIZE == 0 and count > 0:
        cursor.execute('COMMIT')
        cursor.execute('BEGIN')
        sys.stdout.write('.'); sys.stdout.flush()
cursor.execute('COMMIT')
print()
"

cat /sys/block/nvme0n1/stat > /tmp/stat_after.txt
sync

GC_COUNT=$(grep -c "f2fs_gc_begin" /sys/kernel/debug/tracing/trace)
echo "GC cycles: $GC_COUNT"
if [ $GC_COUNT -eq 0 ]; then
  echo "Adding emergency writes..."
  python3 -c "
import sqlite3, random, os
conn = sqlite3.connect('$DB')
cursor = conn.cursor()
BATCH_SIZE = 10000
cursor.execute('BEGIN')
for count in range(2000000):
    cursor.execute('UPDATE data SET value=? WHERE id=?', 
                  (os.urandom(1024), random.randint(1, 10000000)))
    if count % BATCH_SIZE == 0 and count > 0:
        cursor.execute('COMMIT')
        cursor.execute('BEGIN')
cursor.execute('COMMIT')
  "
fi

LOGICAL=$(( (10000000 + 3*1000000) * 1024 ))
echo $LOGICAL > /tmp/logical.txt
echo "Logical: $(($LOGICAL/1024/1024/1024)) GB"