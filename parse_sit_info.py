import re
import math
import argparse
from collections import Counter
import os
import matplotlib.pyplot as plt

# --- Configuration ---
MAX_VBLOCKS = 512  
PARTITION_SIZE_PERCENT = 2 
DEFAULT_FILENAME = "sit_info.txt"
OUTPUT_CDF_IMAGE_FILE = "vblock_cdf_percentage.png" # Changed output file name

# The existing parse_f2fs_summary function remains the same
def parse_f2fs_summary(file_path):
    """
    Reads summary data from the specified file path, parses lines, and filters entries.
    """
    
    if not os.path.exists(file_path):
        print(f"❌ Error: File not found at '{file_path}'")
        return None, 0

    # Regular expression to capture the required fields: Segment no.: <segno>, Valid: <vblocks>, type: <seg_type>
    pattern = re.compile(
        r'Segment no.:\s*(?P<segno>\d+)'
        r'.*Valid:\s*(?P<vblocks>\d+)'
        r'.*type:\s*(?P<seg_type>\d+)'
    )

    filtered_vblock_percentages = []
    total_lines_read = 0
    valid_seg_types = {0, 1, 2}

    try:
        with open(file_path, 'r') as f:
            for line in f:
                total_lines_read += 1
                match = pattern.search(line)
                
                if match:
                    vblocks = int(match.group('vblocks'))
                    seg_type = int(match.group('seg_type'))
                    
                    if seg_type in valid_seg_types:
                        vblocks_clamped = min(vblocks, MAX_VBLOCKS) 
                        vblock_percent = (vblocks_clamped / MAX_VBLOCKS) * 100
                        filtered_vblock_percentages.append(vblock_percent)
                        
    except Exception as e:
        print(f"An error occurred while reading or processing the file: {e}")
        return None, 0
        
    return filtered_vblock_percentages, total_lines_read


def create_histogram(percentages, partition_size):
    """
    Creates a standard frequency histogram and returns the raw sorted bins.
    """
    
    bin_counts = Counter()
    
    for p in percentages:
        if p == 100:
            bin_index = 19
        else:
            bin_index = max(0, min(19, math.floor(p / partition_size))) 
            
        bin_start = bin_index * partition_size
        bin_counts[bin_start] += 1
        
    # Create sorted list of (start_percent, count) tuples
    sorted_bins = sorted(bin_counts.items())
    print(sorted_bins[-1])
    return sorted_bins


def create_cumulative_distribution(sorted_bins, total_segments):
    """
    Converts the sorted histogram bins into cumulative PERCENTAGES.
    """
    cumulative_percentages = {}
    current_cumulative_count = 0
    
    if total_segments == 0:
        return cumulative_percentages

    for start_percent, count in sorted_bins:
        current_cumulative_count += count
        
        # Calculate the cumulative percentage
        cumulative_pct = (current_cumulative_count / total_segments) * 100
        
        # The x-axis point for a CDF is the END of the bin (e.g., 5%, 10%, etc.)
        end_percent = min(start_percent + PARTITION_SIZE_PERCENT, 100)
        
        # Store the cumulative percentage at the bin's end point
        cumulative_percentages[end_percent] = cumulative_pct
        
    return cumulative_percentages


def plot_cumulative_distribution(cumulative_percentages, output_file):
    """
    Generates and saves a line plot of the Cumulative Distribution Function (CDF)
    with the Y-axis scaled to a percentage.
    """
    if not cumulative_percentages:
        print("No data to plot.")
        return

    # Prepare x (percentage) and y (cumulative percentage) values
    percentages = sorted(cumulative_percentages.keys())
    cumulative_pcts = [cumulative_percentages[p] for p in percentages]

    # Prepend (0, 0) for a proper CDF start
    percentages.insert(0, 0)
    cumulative_pcts.insert(0, 0)

    plt.figure(figsize=(10, 6))
    
    # Create the CDF line plot
    plt.plot(percentages, cumulative_pcts, marker='o', linestyle='-', color='purple', linewidth=2)

    # Add labels and title
    plt.title('CDF of Valid Blocks per Segment in F2FS (SQLite-Journal; Zipfian workload)', fontsize=16)
    plt.xlabel('Valid Block Percentage (%)', fontsize=12)
    plt.ylabel('Cumulative Percentage of Segments (%)', fontsize=12) # Y-axis changed
    
    # Set axis limits
    plt.xlim(0, 100)
    plt.ylim(0, 100) # Y-axis max set to 100%
    
    # Add a horizontal line at 100%
    plt.axhline(y=100, color='gray', linestyle='--', linewidth=1)
    
    plt.grid(True, linestyle='--', alpha=0.6)
    plt.tight_layout()
    plt.savefig(output_file)
    plt.close()


def main():
    """
    Main function to handle argument parsing and execution flow.
    """
    
    parser = argparse.ArgumentParser(
        description="F2FS Segment Summary Parser and VBlock Histogram/CDF Generator.",
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

    print(f"🔬 Starting F2FS Segment Summary Parser...")
    print(f"📂 Reading data from: **{file_name}**")
    
    # 1. Parse and Filter
    vblock_percentages, total_lines = parse_f2fs_summary(file_name)
    
    if vblock_percentages is None:
        return 

    total_segments = len(vblock_percentages)
    print(f"Total lines read: {total_lines}")
    print(f"✅ Found {total_segments} qualifying segments (type in 0, 1, 2).")
    
    if not vblock_percentages:
        print("🛑 No segments matched the criteria. Exiting.")
        return

    
    # 2. Create Histogram (raw bins)
    sorted_bins = create_histogram(vblock_percentages, PARTITION_SIZE_PERCENT)

    # 3. Create Cumulative Distribution (in percentage)
    cumulative_percentages = create_cumulative_distribution(sorted_bins, total_segments)
    
    # 4. Plot Cumulative Distribution
    plot_cumulative_distribution(cumulative_percentages, OUTPUT_CDF_IMAGE_FILE)
    print(f"\n🖼️ Cumulative Distribution Plot (as percentage) generated and saved to: {OUTPUT_CDF_IMAGE_FILE}")
    
    # Display the final cumulative distribution table
    print("\n📈 Final Cumulative Distribution Table (Percentage of Total Segments):")
    print("{:<12} | {:<5}".format("VBlock % <=", "Cumulative %"))
    print("-" * 28)
    for percent, cumulative_pct in cumulative_percentages.items():
        # Displaying percentage with 2 decimal places
        print("{:<12} | {:<5.2f}%".format(f"{percent}%", cumulative_pct))


if __name__ == "__main__":
    main()