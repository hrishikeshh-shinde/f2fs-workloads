# enum log_type {
# 	CURSEG_HOT_DATA	= 0,	/* directory entry blocks */
# 	CURSEG_WARM_DATA,	/* data blocks */
# 	CURSEG_COLD_DATA,	/* multimedia or GCed data blocks */
# 	CURSEG_HOT_NODE,	/* direct node blocks of directory files */
# 	CURSEG_WARM_NODE,	/* direct node blocks of normal files */
# 	CURSEG_COLD_NODE,	/* indirect node blocks */
# 	NR_PERSISTENT_LOG,	/* number of persistent log */
# 	CURSEG_COLD_DATA_PINNED = NR_PERSISTENT_LOG,
# 				/* pinned file that needs consecutive block address */
# 	CURSEG_ALL_DATA_ATGC,	/* SSR alloctor in hot/warm/cold data area */
# 	NO_CHECK_TYPE,		/* number of persistent & inmem log */
# };

import re
from collections import Counter
import math

# --- 1. Define the Input Data (Replace this with file reading in a real scenario) ---
f2fs_summary_data = """
segno: 47466 vblocks: 0 seg_type:0 mtime:0 sit_pack:1
segno: 100 vblocks: 512 seg_type:1 mtime:100 sit_pack:1
segno: 200 vblocks: 256 seg_type:2 mtime:20 sit_pack:1
segno: 300 vblocks: 400 seg_type:0 mtime:5 sit_pack:1
segno: 400 vblocks: 50 seg_type:3 mtime:10 sit_pack:1  # seg_type not in (0,1,2)
segno: 500 vblocks: 100 seg_type:1 mtime:0 sit_pack:1  # mtime not > 0
segno: 600 vblocks: 128 seg_type:2 mtime:1 sit_pack:1
segno: 700 vblocks: 512 seg_type:0 mtime:50 sit_pack:1
"""
import re
import math
import argparse
from collections import Counter
import os # Imported for checking if the file exists

# --- Configuration ---
MAX_VBLOCKS = 512  # Maximum number of valid blocks per segment (N_BLOCK_OF_SEGMENT)
PARTITION_SIZE_PERCENT = 5  # Size of each bin in percentage (5%)
DEFAULT_FILENAME = "dump_sit"

def parse_f2fs_summary(file_path):
    """
    Reads summary data from the specified file path, parses lines,
    filters entries, and calculates the percentage of valid blocks.
    """
    
    # Check if the file exists before attempting to open it
    if not os.path.exists(file_path):
        print(f"❌ Error: File not found at '{file_path}'")
        return None, 0

    # Regular expression to capture the required fields
    pattern = re.compile(
        r'segno:\s*(?P<segno>\d+)'
        r'.*vblocks:\s*(?P<vblocks>\d+)'
        r'.*seg_type:\s*(?P<seg_type>\d+)'
        r'.*mtime:\s*(?P<mtime>\d+)'
    )

    filtered_vblock_percentages = []
    total_lines_read = 0
    
    # Required filters
    valid_seg_types = {0, 1, 2}

    try:
        with open(file_path, 'r') as f:
            for line in f:
                total_lines_read += 1
                match = pattern.search(line)
                
                if match:
                    # Convert captured strings to integers
                    vblocks = int(match.group('vblocks'))
                    seg_type = int(match.group('seg_type'))
                    mtime = int(match.group('mtime'))

                    # Apply Filtering Criteria
                    if seg_type in valid_seg_types and mtime > 0:
                        # Calculate percentage of valid blocks
                        # Clamp vblocks at MAX_VBLOCKS just in case of corrupted data
                        vblocks_clamped = min(vblocks, MAX_VBLOCKS) 
                        vblock_percent = (vblocks_clamped / MAX_VBLOCKS) * 100
                        filtered_vblock_percentages.append(vblock_percent)
                        
    except Exception as e:
        print(f"An error occurred while reading or processing the file: {e}")
        return None, 0
        
    return filtered_vblock_percentages, total_lines_read

def create_histogram(percentages, partition_size):
    """
    Creates a histogram from the list of percentages with specified bin size.
    """
    
    bin_counts = Counter()
    
    for p in percentages:
        # Index 0: 0% <= p < 5%
        # Index 19: 95% <= p <= 100%
        
        if p == 100:
            bin_index = 19
        else:
            bin_index = math.floor(p / partition_size)
            
        # Create a user-friendly label for the bin
        bin_start = bin_index * partition_size
        bin_end = min(bin_start + partition_size, 100)
        
        # Format the label, e.g., "5% - 10%"
        bin_label = f"{bin_start}% - {bin_end}%"
        
        bin_counts[bin_label] += 1
        
    return dict(sorted(bin_counts.items()))

def main():
    """
    Main function to handle argument parsing and execution flow.
    """
    
    # Set up argument parser
    parser = argparse.ArgumentParser(
        description="F2FS Segment Summary Parser and VBlock Histogram Generator.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    
    parser.add_argument(
        '--file', 
        type=str, 
        default=DEFAULT_FILENAME,
        help=f"Path to the F2FS summary file.\n(Default: {DEFAULT_FILENAME})"
    )
    
    args = parser.parse_args()
    file_name = args.file

    print(f"🔬 Starting F2FS Segment Summary Parsing...")
    print(f"📂 Attempting to read data from: **{file_name}**")
    print("---")

    # Step 1 & 2: Parse and Filter
    vblock_percentages, total_lines = parse_f2fs_summary(file_name)
    
    if vblock_percentages is None:
        return # Exit on file error

    print(f"Total lines read from file: {total_lines}")
    print(f"✅ Found **{len(vblock_percentages)}** qualifying segments after filtering.")
    print(f"   (Filters: seg_type in (0, 1, 2) AND mtime > 0)")
    
    if not vblock_percentages:
        print("---")
        print("🛑 No segments matched the filtering criteria. Exiting.")
        return

    print("---")

    # Step 3: Create Histogram
    histogram = create_histogram(vblock_percentages, PARTITION_SIZE_PERCENT)

    ## 📊 VBlock Percentage Histogram ##
    
    # Create a table/visual representation of the histogram
    print(f"Histogram (Valid Blocks Percentage) - Bin Size: {PARTITION_SIZE_PERCENT}%")
    print("{:<12} | {:<5}".format("Bin Range", "Count"))
    print("-" * 20)
    for bin_range, count in histogram.items():
        print("{:<12} | {:<5}".format(bin_range, count))

    # Simple visualization
    max_count = max(histogram.values()) if histogram else 0
    if max_count > 0:
        print("\n[Simple Bar Chart]")
        for bin_range, count in histogram.items():
            # Scale to 20 characters for visualization
            bar = "█" * int((count / max_count) * 20)
            print(f"{bin_range}: {bar} ({count})")

if __name__ == "__main__":
    main()