sudo bpftrace -e '
BEGIN {
    printf("inode,page_index,death_time_ms,timestamp\n");
    @start_ts = nsecs;
    @pages_per_blk = 128;
}

tracepoint:f2fs:f2fs_writepage {
    $block_idx = args->index / @pages_per_blk;
    if (@last_updated[args->ino, $block_idx] != 0) {
        $interval_ns = nsecs - @last_updated[args->ino, $block_idx];

        if ($interval_ns > 10000000) {
            // Aggregate the interval into a histogram for this specific page.
            @write_interval[args->ino, $block_idx] = hist($interval_ns/1000000);
            $current_ts = (nsecs - @start_ts) / 1000000;
            printf("%lu, %lu, %lu, %lu\n", args->ino, $block_idx, $interval_ns/1000000, $current_ts);
        }
    }
    
    // Always update the timestamp for the NEXT write calculation.
    @last_updated[args->ino, $block_idx] = nsecs;
} 

END {
    // Manually clear the maps before bpftrace prints them
    clear(@write_interval);
    clear(@last_updated);
    clear(@start_ts);
    clear(@pages_per_blk);
}' > bpftrace_output2.csv &
BPFTRACE_PID=$!

DB_FILE="/mnt/f2fs/sqlite.db"
MODE="DELETE"

rm -f $DB_FILE
PYTHON_SCRIPT="
import sqlite3, os, time, sys, random
conn = sqlite3.connect('$DB_FILE')
conn.execute('PRAGMA journal_mode=$MODE')
conn.execute('PRAGMA synchronous=NORMAL')
conn.execute('CREATE TABLE IF NOT EXISTS data (id INTEGER PRIMARY KEY, val BLOB)')

# 1. INSERT CHUNK (Expand DB size)
# Insert 100,000 rows (~100MB)
c = conn.cursor()
c.execute('BEGIN')
blob = os.urandom(1024)
start_id = int(sys.argv[1])
for i in range(start_id, start_id + 200000):
    c.execute('INSERT INTO data VALUES (?, ?)', (i, blob))
c.execute('COMMIT')

# 2. FRAGMENT CHUNK (Create Zombies)
# Update 20,000 random rows to create holes
c.execute('BEGIN')
for _ in range(200000):
    # Update random ID in current range
    rid = random.randint(0, start_id + 5000)
    c.execute('UPDATE data SET val=? WHERE id=?', (os.urandom(1024), rid))
    if _ % 100 == 0: # Frequent commits
        c.execute('COMMIT'); c.execute('BEGIN')
c.execute('COMMIT')
conn.close()
"

# for (( j=0; j<10; j++ ))
# do
#     echo $j * 100000
#     # python3 -c "$PYTHON_SCRIPT" $j * 100000
# done
python3 -c "$PYTHON_SCRIPT" 0


echo "Stopping bpftrace"
sudo kill -SIGINT $BPFTRACE_PID
wait $BPFTRACE_PID