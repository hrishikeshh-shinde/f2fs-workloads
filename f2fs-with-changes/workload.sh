
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
echo "Formatting filesystem..."

# Force unmount and clean up
umount $MOUNT_POINT 2>/dev/null
umount $DEV 2>/dev/null

# Check if device exists
if [ ! -b "$DEV" ]; then
    echo "ERROR: Device $DEV does not exist!"
    exit 1
fi

# Check if device is busy
echo "Checking if device is busy..."
if lsof $DEV >/dev/null 2>&1; then
    echo "ERROR: Device $DEV is in use by another process!"
    lsof $DEV
    exit 1
fi

# Format with timeout
echo "Running mkfs.f2fs (this may take a moment)..."
timeout 30s mkfs.f2fs -f $DEV
if [ $? -ne 0 ]; then
    echo "ERROR: mkfs.f2fs failed or timed out!"
    echo "Trying alternative approach..."
    
    # Try to check device status
    echo "Device info:"
    fdisk -l $DEV 2>/dev/null || echo "Cannot read device info"
    exit 1
fi

echo "Formatting completed successfully."

# Create mount point if needed
if [ ! -d "$MOUNT_POINT" ]; then 
    mkdir -p $MOUNT_POINT
fi

# Mount with options for better performance
mount -t f2fs -o mode=lfs,discard,no_heap $DEV $MOUNT_POINT
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to mount $DEV at $MOUNT_POINT"
    exit 1
fi

echo "Filesystem mounted at $MOUNT_POINT"

# Prepare Trace
echo 0 > /sys/kernel/debug/tracing/trace 2>/dev/null
echo 1 > /sys/kernel/debug/tracing/events/f2fs/f2fs_gc_begin/enable 2>/dev/null
echo 1 > /sys/kernel/debug/tracing/events/f2fs/f2fs_gc_end/enable 2>/dev/null
echo 1 > /sys/kernel/debug/tracing/tracing_on 2>/dev/null

# Initialize Result File
echo "Disk_Used_MB,Time_Seconds,GC_Events" > $CSV_FILE
echo "=========================================================="
echo " Starting Progressive Fill Test ($MODE)"
echo " Results will be saved to: $CSV_FILE"
echo "=========================================================="

# 2. RUN LOOP UNTIL DISK IS 90% FULL
PYTHON_SCRIPT="
import sqlite3, os, time, sys, random

def run_workload(start_id, mode):
    # Debug output
    print(f'[PYTHON] Starting with start_id={start_id}, mode={mode}', file=sys.stderr)
    
    conn = sqlite3.connect('$DB_FILE')
    conn.execute(f'PRAGMA journal_mode={mode}')
    conn.execute('PRAGMA synchronous=NORMAL')
    conn.execute('CREATE TABLE IF NOT EXISTS data (id INTEGER PRIMARY KEY, val BLOB)')
    
    c = conn.cursor()
    
    # Check existing data
    c.execute('SELECT COUNT(*), MIN(id), MAX(id) FROM data')
    result = c.fetchone()
    if result[0] is not None:
        count, min_id, max_id = result
        print(f'[PYTHON] Before insert: {count} rows, min={min_id}, max={max_id}', file=sys.stderr)
    else:
        print('[PYTHON] Before insert: Table is empty', file=sys.stderr)
    
    # INSERT 100K rows
    c.execute('BEGIN')
    blob = os.urandom(1024)
    end_id = start_id + 100000
    
    print(f'[PYTHON] Inserting {start_id} to {end_id-1}', file=sys.stderr)
    
    inserted = 0
    for i in range(start_id, end_id):
        try:
            c.execute('INSERT INTO data VALUES (?, ?)', (i, blob))
            inserted += 1
        except sqlite3.IntegrityError as e:
            print(f'[PYTHON] ERROR at id={i}: {e}', file=sys.stderr)
            raise
        except Exception as e:
            print(f'[PYTHON] Unexpected error at id={i}: {e}', file=sys.stderr)
            raise
    
    c.execute('COMMIT')
    print(f'[PYTHON] Insert completed successfully. Inserted {inserted} rows', file=sys.stderr)
    
    # Check after insert
    c.execute('SELECT COUNT(*) FROM data')
    new_count = c.fetchone()[0]
    print(f'[PYTHON] After insert: {new_count} rows total', file=sys.stderr)
    
    # UPDATE 1000 random existing rows
    c.execute('BEGIN')
    for _ in range(1000):
        # Only update rows that exist (0 to current max)
        c.execute('SELECT MAX(id) FROM data')
        max_id = c.fetchone()[0]
        if max_id is None or max_id <= 0:
            print('[PYTHON] No rows to update', file=sys.stderr)
            break
        
        rid = random.randint(0, max_id)
        c.execute('UPDATE data SET val=? WHERE id=?', (os.urandom(1024), rid))
        
        if _ % 100 == 0:
            c.execute('COMMIT')
            c.execute('BEGIN')
    
    c.execute('COMMIT')
    print('[PYTHON] Update completed successfully', file=sys.stderr)
    conn.close()

# Run the workload
if __name__ == '__main__':
    start_id = int(sys.argv[1])
    run_workload(start_id, '$MODE')
"

ROW_COUNTER=0
ROUND=1

while true; do
    # Get disk usage BEFORE the workload
    USED_KB=$(df -k $MOUNT_POINT 2>/dev/null | tail -1 | awk '{print $3}')
    TOTAL_KB=$(df -k $MOUNT_POINT 2>/dev/null | tail -1 | awk '{print $2}')
    
    if [ -z "$USED_KB" ] || [ -z "$TOTAL_KB" ]; then
        echo "ERROR: Cannot get disk usage. Filesystem might be unmounted."
        break
    fi
    
    USED_MB=$((USED_KB / 1024))
    PERCENT=$((USED_KB * 100 / TOTAL_KB))
    
    echo "=== Round $ROUND ==="
    echo "Starting with: ${USED_MB}MB (${PERCENT}%) full"
    echo "ROW_COUNTER = $ROW_COUNTER"
    
    if [ $PERCENT -ge 90 ]; then
        echo "Disk 90% full. Stopping."
        break
    fi
    
    # Clear trace buffer
    echo 0 > /sys/kernel/debug/tracing/trace 2>/dev/null
    
    # Run the workload with timing
    START_TIME=$(date +%s.%N)
    python3 -c "$PYTHON_SCRIPT" "$ROW_COUNTER"
    EXIT_CODE=$?
    END_TIME=$(date +%s.%N)
    
    if [ $EXIT_CODE -ne 0 ]; then
        echo "ERROR: Python script failed with exit code $EXIT_CODE"
        echo "Debug info:"
        echo "ROW_COUNTER was: $ROW_COUNTER"
        echo "Current disk usage: ${USED_MB}MB (${PERCENT}%)"
        break
    fi
    
    DURATION=$(echo "$END_TIME - $START_TIME" | bc)
    GC_COUNT=$(grep -c "f2fs_gc_begin" /sys/kernel/debug/tracing/trace 2>/dev/null || echo "0")
    
    echo "Round $ROUND | Used: ${USED_MB}MB (${PERCENT}%) | Time: ${DURATION}s | GC: $GC_COUNT"
    echo "${USED_MB},${DURATION},${GC_COUNT}" >> $CSV_FILE
    
    ROW_COUNTER=$((ROW_COUNTER + 100000))
    ROUND=$((ROUND + 1))
    
    # Small pause to ensure filesystem settles
    sleep 1
done

echo "Test Complete. Data in $CSV_FILE"

# Clean up
echo 0 > /sys/kernel/debug/tracing/tracing_on 2>/dev/null
#umount $MOUNT_POINT 2>/dev/null
#echo "Unmounted $MOUNT_POINT"
