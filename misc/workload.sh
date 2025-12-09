cat > workload.sh << 'EOF'
#!/bin/bash

# ==============================================================================
# F2FS PROGRESSIVE ZOMBIE TEST
# ==============================================================================
# Goal: Run SQLite continuously until disk is full.
# We measure performance at 10%, 20%, ... 90% usage.
# This PROVES that performance degrades as "Zombies" accumulate.
# ==============================================================================

DEV="/dev/nvme0n1"
MOUNT_POINT="/mnt/femu"
DB_FILE="$MOUNT_POINT/test.db"
CSV_FILE="results_progressive.csv"

# Check for root
if [ "$EUID" -ne 0 ]; then echo "Run as sudo"; exit 1; fi

MODE=$1
if [[ "$MODE" != "DELETE" && "$MODE" != "WAL" ]]; then
    echo "Usage: $0 {DELETE|WAL}"
    exit 1
fi

# 1. SETUP
umount $MOUNT_POINT 2>/dev/null
mkfs.f2fs -f $DEV > /dev/null
if [ ! -d "$MOUNT_POINT" ]; then mkdir -p $MOUNT_POINT; fi
mount -t f2fs $DEV $MOUNT_POINT

# Prepare Trace
echo 0 > /sys/kernel/debug/tracing/trace
echo 1 > /sys/kernel/debug/tracing/events/f2fs/f2fs_gc_begin/enable
echo 1 > /sys/kernel/debug/tracing/events/f2fs/f2fs_gc_end/enable
echo 1 > /sys/kernel/debug/tracing/tracing_on

# Initialize Result File
echo "Disk_Used_MB,Time_Seconds,GC_Events" > $CSV_FILE
echo "=========================================================="
echo " Starting Progressive Fill Test ($MODE)"
echo " Results will be saved to: $CSV_FILE"
echo "=========================================================="

# 2. RUN LOOP UNTIL DISK IS 95% FULL
PYTHON_SCRIPT="
import sqlite3, os, time, sys, random
conn = sqlite3.connect('$DB_FILE')
conn.execute('PRAGMA journal_mode=$MODE')
conn.execute('PRAGMA synchronous=NORMAL')
conn.execute('CREATE TABLE IF NOT EXISTS data (id INTEGER PRIMARY KEY, val BLOB)')

c = conn.cursor()
c.execute('BEGIN')
blob = os.urandom(1024)
start_id = int(sys.argv[1])
for i in range(start_id, start_id + 100000):
    c.execute('INSERT INTO data VALUES (?, ?)', (i, blob))
c.execute('COMMIT')

c.execute('BEGIN')
for _ in range(1000):
    rid = random.randint(0, start_id + 100000)
    c.execute('UPDATE data SET val=? WHERE id=?', (os.urandom(1024), rid))
    if _ % 100 == 0:
        c.execute('COMMIT'); c.execute('BEGIN')
c.execute('COMMIT')
conn.close()
"

ROW_COUNTER=0
ROUND=1

while true; do
    USED_KB=$(df -k $MOUNT_POINT | tail -1 | awk '{print $3}')
    TOTAL_KB=$(df -k $MOUNT_POINT | tail -1 | awk '{print $2}')
    USED_MB=$((USED_KB / 1024))
    PERCENT=$((USED_KB * 100 / TOTAL_KB))

    if [ $PERCENT -ge 90 ]; then
        echo "Disk 90% full. Stopping."
        break
    fi

    echo 0 > /sys/kernel/debug/tracing/trace
    
    START_TIME=$(date +%s.%N)
    python3 -c "$PYTHON_SCRIPT" "$ROW_COUNTER"
    END_TIME=$(date +%s.%N)
    
    DURATION=$(echo "$END_TIME - $START_TIME" | bc)
    GC_COUNT=$(grep -c "f2fs_gc_begin" /sys/kernel/debug/tracing/trace)
    
    echo "Round $ROUND | Used: ${USED_MB}MB (${PERCENT}%) | Time: ${DURATION}s | GC: $GC_COUNT"
    echo "${USED_MB},${DURATION},${GC_COUNT}" >> $CSV_FILE
    
    ROW_COUNTER=$((ROW_COUNTER + 100000))
    ROUND=$((ROUND + 1))
done

echo "Test Complete. Data in $CSV_FILE"
EOF

chmod +x workload.sh