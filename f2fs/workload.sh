#!/bin/bash
# ==============================================================================
# F2FS EXPERIMENT: GENTLE WORKLOAD (Reaches 90% Capacity)
# ==============================================================================

DEV="/dev/nvme0n1"
MOUNT_POINT="/mnt/femu"
DB_FILE="$MOUNT_POINT/bench.db"
RESULT_DIR="f2fs_gentle_results"
mkdir -p $RESULT_DIR

# TIMEOUT: 600 seconds (10 minutes) per round. 
# If a round takes longer, we assume GC death and stop.
TIMEOUT_SEC=600

# Check for root
if [ "$EUID" -ne 0 ]; then echo "Run as sudo"; exit 1; fi

# --- 1. SETUP ---
echo "[Setup] Formatting F2FS (LFS Mode)..."
umount $MOUNT_POINT 2>/dev/null

# Force LFS mode to expose allocator behavior (No IPU masking)
mkfs.f2fs -f $DEV > /dev/null
mount -t f2fs -o mode=lfs $DEV $MOUNT_POINT

# Enable Tracing
echo 0 > /sys/kernel/debug/tracing/trace
echo 1 > /sys/kernel/debug/tracing/events/f2fs/f2fs_gc_begin/enable
echo 1 > /sys/kernel/debug/tracing/tracing_on

# Reset Disk Stats for WAF calculation
cat /sys/block/${DEV##*/}/stat > /tmp/stat_start.txt

# CSV Header
echo "Round,Disk_Percent,Time_Sec,Dirty_Segs,Free_Segs,GC_Events,Physical_MB" > "$RESULT_DIR/metrics.csv"

# --- 2. WORKLOAD DEFINITION (GENTLER VERSION) ---
# 100MB Inserts + 1MB Updates (1000 random writes)
PYTHON_WORKLOAD="
import sqlite3, os, sys, random
conn = sqlite3.connect('$DB_FILE')
conn.execute('PRAGMA journal_mode=DELETE')
conn.execute('PRAGMA synchronous=NORMAL')
conn.execute('CREATE TABLE IF NOT EXISTS t (id INTEGER PRIMARY KEY, v BLOB)')

c = conn.cursor()

# A. Insert (100MB) - Keeps the drive filling up
c.execute('BEGIN')
blob = os.urandom(1024)
start = int(sys.argv[1])
for i in range(start, start + 100000):
    c.execute('INSERT INTO t VALUES (?, ?)', (i, blob))
c.execute('COMMIT')

# B. Fragment (1000 random updates) - The 'Gentle' Zombie Generator
# We update ~1% of the data volume to create steady fragmentation
c.execute('BEGIN')
for _ in range(1000):
    rid = random.randint(0, start + 100000)
    c.execute('UPDATE t SET v=? WHERE id=?', (os.urandom(1024), rid))
    
    # Batch 500: Groups writes slightly to avoid instant metadata thrashing
    if _ % 500 == 0: c.execute('COMMIT'); c.execute('BEGIN')
c.execute('COMMIT')
"

# --- 3. EXECUTION LOOP ---
ROW=0
ROUND=1
echo "Starting Experiment (Watchdog: ${TIMEOUT_SEC}s)..."
echo "Results will be saved to: $RESULT_DIR/metrics.csv"

while true; do
    # Check Disk Usage
    USED_KB=$(df -k $MOUNT_POINT | tail -1 | awk '{print $3}')
    TOTAL_KB=$(df -k $MOUNT_POINT | tail -1 | awk '{print $2}')
    PCT=$((USED_KB * 100 / TOTAL_KB))
    
    # Stop workload at 95%
    if [ $PCT -ge 95 ]; then 
        echo "Disk 95% Full. Stopping Experiment Successfully."
        break
    fi

    echo ">>> Round $ROUND (Disk: $PCT%)"
    
    # Run Workload with TIMEOUT
    START_T=$(date +%s)
    
    # This runs the python script in background. Kills it if > 10 mins.
    timeout -k 10s $TIMEOUT_SEC python3 -c "$PYTHON_WORKLOAD" "$ROW"
    EXIT_CODE=$?
    
    END_T=$(date +%s)
    DURATION=$((END_T - START_T))

    # CAPTURE METRICS
    cp /sys/kernel/debug/f2fs/status "$RESULT_DIR/status_$ROUND.txt"
    DIRTY=$(grep -m 1 "Dirty" "$RESULT_DIR/status_$ROUND.txt" | awk -F: '{print $2}' | tr -d ' ,')
    FREE=$(grep -m 1 "Free" "$RESULT_DIR/status_$ROUND.txt" | awk -F: '{print $2}' | tr -d ' ,')
    GC_COUNT=$(grep -c "f2fs_gc_begin" /sys/kernel/debug/tracing/trace)
    
    NOW_STAT=$(cat /sys/block/${DEV##*/}/stat | awk '{print $7}')
    START_STAT=$(awk '{print $7}' /tmp/stat_start.txt)
    PHYSICAL_MB=$(( (NOW_STAT - START_STAT) * 512 / 1024 / 1024 ))

    echo "$ROUND,$PCT,$DURATION,$DIRTY,$FREE,$GC_COUNT,$PHYSICAL_MB" >> "$RESULT_DIR/metrics.csv"
    
    # CHECK FOR HANG/TIMEOUT
    if [ $EXIT_CODE -eq 124 ]; then
        echo "!!! CRITICAL: WORKLOAD TIMED OUT (GC WALL HIT) !!!"
        echo "The system took > $TIMEOUT_SEC seconds."
        echo "Final,HANG,$DURATION,$DIRTY,$FREE,$GC_COUNT,$PHYSICAL_MB" >> "$RESULT_DIR/metrics.csv"
        break
    fi

    ROW=$((ROW + 100000))
    ROUND=$((ROUND + 1))
done

echo "Experiment Complete."