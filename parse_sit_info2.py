import re
import math
import argparse
from collections import Counter
import os
import matplotlib.pyplot as plt

# --- Configuration ---
MAX_VBLOCKS = 512  
PARTITION_SIZE_PERCENT = 2
# Changed default to a list for demonstration purposes, though one file is fine too
DEFAULT_FILENAMES = ["sit_info.txt", "sit_info_predict.txt"] 
OUTPUT_CDF_IMAGE_FILE = "vblock_cdf_comparison.png" 

# --- Parsing and Data Preparation Functions (Minimal Changes) ---

def parse_f2fs_summary(file_path):
    """
    Reads summary data from the specified file path, parses lines, and filters entries.
    (Function body is unchanged from previous revision)
    """
    
    if not os.path.exists(file_path):
        print(f"❌ Error: File not found at '{file_path}'")
        return None, 0

    pattern = re.compile(
        r'Segment no.:\s*(?P<segno>\d+)'
        r'.*Valid:\s*(?P<vblocks>\d+)'
        r'.*type:\s*(?P<seg_type>\d+)'
    )

    filtered_vblock_percentages = []
    total_lines_read = 0
    valid_seg_types = {0, 1, 2}
    max_vblock_percent = 0

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
                        max_vblock_percent = max(max_vblock_percent, vblock_percent)
                        filtered_vblock_percentages.append(vblock_percent)
        print(f"Max vblock percent from {file_path}: {max_vblock_percent}")
    except Exception as e:
        print(f"An error occurred while reading or processing the file: {e}")
        return None, 0
        
    return filtered_vblock_percentages, total_lines_read


def create_histogram(percentages, partition_size):
    """
    Creates a standard frequency histogram and returns the raw sorted bins.
    (Function body is unchanged from previous revision)
    """
    
    bin_counts = Counter()
    
    for p in percentages:
        if p == 100:
            bin_index = 19
        else:
            bin_index = max(0, min(19, math.floor(p / partition_size))) 
            
        bin_start = bin_index * partition_size
        bin_counts[bin_start] += 1
        
    sorted_bins = sorted(bin_counts.items())
    print(sorted_bins[-1])
        
    return sorted_bins


def create_cumulative_distribution(sorted_bins, total_segments):
    """
    Converts the sorted histogram bins into cumulative PERCENTAGES.
    (Function body is unchanged from previous revision)
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
        
        cumulative_percentages[end_percent] = cumulative_pct
        
    return cumulative_percentages


## Updated Plotting Function: Accepts Multiple Datasets ##
def plot_cumulative_comparison(all_cdf_data, output_file):
    """
    Generates and saves a line plot of multiple Cumulative Distribution Functions (CDFs)
    on the same graph for comparison.
    
    :param all_cdf_data: List of tuples, where each tuple is (filename, cdf_data_dict)
    """
    if not all_cdf_data:
        print("No data to plot.")
        return

    plt.figure(figsize=(10, 6))
    
    # Define markers and colors for distinct plots
    styles = [
        ('o', '#3498db', 'File 1'), 
        ('s', '#e74c3c', 'File 2'), 
        ('^', '#2ecc71', 'File 3'), 
        ('d', '#f39c12', 'File 4')
    ]

    for i, (filename, cdf_data) in enumerate(all_cdf_data):
        marker, color, base_label = styles[i % len(styles)]
        
        percentages = sorted(cdf_data.keys())
        cumulative_pcts = [cdf_data[p] for p in percentages]

        # Prepend (0, 0) for a proper CDF start
        percentages.insert(0, 0)
        cumulative_pcts.insert(0, 0)
        label = "Default policies"
        if filename == "sit_info_predict.txt":
            label = "With death-time prediction"
        
        # Plot the CDF line
        plt.plot(
            percentages, 
            cumulative_pcts, 
            marker=marker, 
            linestyle='-', 
            color=color, 
            linewidth=2,
            label=f'{label}' # Use the filename as the legend label
        )

    # Add labels and title
    plt.title('F2FS Segment Valid Blocks CDF', fontsize=16)
    plt.xlabel('Valid Block %', fontsize=12)
    plt.ylabel('Cumulative % of Segments', fontsize=12)
    
    # Final plot settings
    plt.xlim(0, 100)
    plt.ylim(0, 100)
    
    plt.axhline(y=100, color='gray', linestyle='--', linewidth=1)
    plt.grid(True, linestyle='--', alpha=0.6)
    plt.legend(loc='lower right', title="Policies")
    plt.tight_layout()
    plt.savefig(output_file)
    plt.close()


def main():
    """
    Main function to handle argument parsing, data processing, and plotting.
    """
    
    parser = argparse.ArgumentParser(
        description="F2FS Segment Summary Parser for Comparative CDF Plotting.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    
    parser.add_argument(
        '--files', 
        nargs='+',  # This tells argparse to accept one or more arguments
        type=str, 
        default=DEFAULT_FILENAMES,
        help=f"List of paths to the F2FS summary files (space separated).\n(Default: {', '.join(DEFAULT_FILENAMES)})"
    )
    
    args = parser.parse_args()
    file_names = args.files
    
    all_cdf_data = []

    print(f"🔬 Starting F2FS Comparative Analysis for {len(file_names)} files...")

    # --- 1. Loop through all input files ---
    for file_name in file_names:
        print(f"\n📂 Processing file: **{file_name}**")
        
        vblock_percentages, total_lines = parse_f2fs_summary(file_name)
        
        if vblock_percentages is None:
            continue # Skip to next file on error

        total_segments = len(vblock_percentages)
        print(f"Total lines read: {total_lines}")
        print(f"✅ Found {total_segments} qualifying segments.")
        
        if not vblock_percentages:
            print(f"🛑 No segments found in {file_name}. Skipping plot for this file.")
            continue

        # 2. Create Histogram (raw bins)
        sorted_bins = create_histogram(vblock_percentages, PARTITION_SIZE_PERCENT)

        # 3. Create Cumulative Distribution (in percentage)
        cumulative_percentages = create_cumulative_distribution(sorted_bins, total_segments)
        
        # Store data for plotting
        all_cdf_data.append((file_name, cumulative_percentages))
        
        # Display the final cumulative distribution table for this file
        print("📈 Sample Cumulative Distribution Points:")
        print("{:<12} | {:<5}".format("VBlock % <=", "Cumulative %"))
        print("-" * 28)
        # Display a few key points for inspection (e.g., 0%, 50%, 100%)
        display_points = [p for p in cumulative_percentages if p % 50 == 0 or p == 5]
        for percent in sorted(display_points):
            print("{:<12} | {:<5.2f}%".format(f"{percent}%", cumulative_percentages[percent]))


    # --- 2. Generate Comparison Plot ---
    if len(all_cdf_data) >= 1:
        plot_cumulative_comparison(all_cdf_data, OUTPUT_CDF_IMAGE_FILE)
        print(f"\n\n🖼️ Comparison CDF Plot generated and saved to: **{OUTPUT_CDF_IMAGE_FILE}**")
    else:
        print("\n🛑 No valid data found across all files. Cannot generate plot.")


if __name__ == "__main__":
    main()