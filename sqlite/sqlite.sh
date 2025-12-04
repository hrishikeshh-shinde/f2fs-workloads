#!/bin/bash
echo "=== SQLite DELETE 10M Test ==="

umount /mnt/femu 2>/dev/null; mkfs.f2fs -f /dev/nvme0n1; mount -t f2fs /dev/nvme0n1 /mnt/femu
echo 1 > /sys/kernel/debug/tracing/events/f2fs/f2fs_gc_begin/enable
echo 1 > /sys/kernel/debug/tracing/events/f2fs/f2fs_gc_end/enable
echo 1 > /sys/kernel/debug/tracing/tracing_on
echo > /sys/kernel/debug/tracing/trace
cat /sys/block/nvme0n1/stat > /tmp/stat_before.txt

DB="/mnt/femu/sqlite_delete.db"
rm -f $DB*
sqlite3 $DB "PRAGMA journal_mode=DELETE; CREATE TABLE data (id INTEGER PRIMARY KEY, value BLOB);"

# Insert 10M
echo "Insert 10M rows..."
python3 -c "
import sqlite3, os, sys
conn = sqlite3.connect('$DB')
c = conn.cursor()
BATCH = 10000
for batch_start in range(1, 10000001, BATCH):
    c.execute('BEGIN')
    for i in range(batch_start, min(batch_start + BATCH, 10000001)):
        c.execute('INSERT INTO data VALUES (?, ?)', (i, os.urandom(1024)))
    c.execute('COMMIT')
    if batch_start % 100000 == 0:
        sys.stdout.write('.'); sys.stdout.flush()
        if batch_start % 1000000 == 0:
            print(f' {batch_start//1000000}M')
print()
"

# Verify
COUNT=$(sqlite3 $DB "SELECT COUNT(*) FROM data;")
echo "Verify: $COUNT rows"
[ $COUNT -lt 9000000 ] && echo "ERROR: Inserts failed" && exit 1

# Update 1M × 3
echo "Update 1M × 3..."
for r in {1..3}; do
  python3 -c "
import sqlite3, random, os, sys
conn = sqlite3.connect('$DB')
c = conn.cursor()
BATCH = 10000
c.execute('BEGIN')
for count in range(1000000):
    c.execute('UPDATE data SET value=? WHERE id=?', 
             (os.urandom(1024), random.randint(1, 10000000)))
    if count % BATCH == 0 and count > 0:
        c.execute('COMMIT')
        c.execute('BEGIN')
    if count % 100000 == 0:
        sys.stdout.write('.'); sys.stdout.flush()
c.execute('COMMIT')
print()
  "
done

# Delete 2M
echo "Delete 2M rows..."
python3 -c "
import sqlite3, random, sys
conn = sqlite3.connect('$DB')
c = conn.cursor()
BATCH = 10000
c.execute('BEGIN')
for count in range(2000000):
    c.execute('DELETE FROM data WHERE id=?', (random.randint(1, 10000000),))
    if count % BATCH == 0 and count > 0:
        c.execute('COMMIT')
        c.execute('BEGIN')
    if count % 100000 == 0:
        sys.stdout.write('.'); sys.stdout.flush()
c.execute('COMMIT')
print()
"

# Final
cat /sys/kernel/debug/tracing/trace > /tmp/gc_trace_delete.txt
cat /sys/block/nvme0n1/stat > /tmp/stat_after.txt
sync

echo ""
echo "=== RESULTS ==="
GC_COUNT=$(grep -c "f2fs_gc_begin" /tmp/gc_trace_delete.txt)
echo "GC cycles: $GC_COUNT"

# GC time
python3 -c "
import re
with open('/tmp/gc_trace_delete.txt') as f:
    lines = f.readlines()
begins = []; ends = []
for line in lines:
    if 'f2fs_gc_begin' in line:
        m = re.search(r'(\d+\.\d+):', line)
        if m: begins.append(float(m.group(1)))
    elif 'f2fs_gc_end' in line:
        m = re.search(r'(\d+\.\d+):', line)
        if m: ends.append(float(m.group(1)))
total = 0
for i in range(min(len(begins), len(ends))):
    dur = ends[i] - begins[i]
    total += dur
print(f'Total GC time: {total:.3f}s')
if begins:
    print(f'Average GC time: {total/len(begins):.3f}s')
"

# WAF
BEFORE=$(awk '{print $7}' /tmp/stat_before.txt)
AFTER=$(awk '{print $7}' /tmp/stat_after.txt)
LOGICAL=$(( (10000000 + 3*1000000) * 1024 ))
DELTA=$((AFTER - BEFORE))
PHYSICAL=$((DELTA * 512))
WAF=$(echo "scale=3; $PHYSICAL / $LOGICAL" | bc)
echo "WAF: $WAF (Physical: $(($PHYSICAL/1024/1024/1024)) GB, Logical: $(($LOGICAL/1024/1024/1024)) GB)"