import matplotlib.pyplot as plt
import csv
import sys

# Usage: python3 pot.py metrics.csv
if len(sys.argv) < 2:
    print("Usage: python3 pot.py <path_to_csv>")
    sys.exit(1)

file_path = sys.argv[1]

rounds = []
disk_pct = []
dirty_segs = []
free_segs = []
gc_events = []
physical_mb = []

def clean_int(value):
    """
    Helper to turn '8060(8060)' into integer 8060.
    """
    if not value: return 0
    # Split by '(' to handle cases like "8060(8060)" and take the first part
    clean_val = value.split('(')[0]
    return int(clean_val)

try:
    with open(file_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Skip the "Final" summary line if it exists
            if row['Round'] == 'Final' or row['Round'] == 'HANG':
                continue
            
            try:
                rounds.append(int(row['Round']))
                disk_pct.append(int(row['Disk_Percent']))
                
                # Apply the cleaning function to these columns
                dirty_segs.append(clean_int(row['Dirty_Segs']))
                free_segs.append(clean_int(row['Free_Segs']))
                
                gc_events.append(int(row['GC_Events']))
                physical_mb.append(int(row['Physical_MB']))
            except ValueError as e:
                print(f"Skipping malformed row: {row} - Error: {e}")
                continue

    # 1. Plot A: Dirty Segments (The Zombie Curve)
    plt.figure(figsize=(10, 6))
    plt.plot(disk_pct, dirty_segs, label='Dirty Segments', color='orange', linewidth=2)
    plt.xlabel('Disk Utilization (%)')
    plt.ylabel('Count of Dirty Segments')
    plt.title('Internal Fragmentation vs Disk Usage')
    plt.grid(True, which='both', linestyle='--', alpha=0.7)
    plt.legend()
    plt.savefig('graph_fragmentation.png')
    print("Saved graph_fragmentation.png")

    # 2. Plot B: GC Events (System Stress)
    plt.figure(figsize=(10, 6))
    plt.plot(disk_pct, gc_events, label='GC Events', color='red', linewidth=2)
    plt.xlabel('Disk Utilization (%)')
    plt.ylabel('Cumulative GC Events')
    plt.title('Garbage Collection Overhead')
    plt.grid(True, linestyle='--', alpha=0.7)
    plt.legend()
    plt.savefig('graph_gc_stress.png')
    print("Saved graph_gc_stress.png")

    # 3. Plot C: Free Segments (Efficiency)
    plt.figure(figsize=(10, 6))
    plt.plot(disk_pct, free_segs, label='Free Segments', color='green', linewidth=2)
    plt.xlabel('Disk Utilization (%)')
    plt.ylabel('Free Segments Available')
    plt.title('Free Space Availability')
    plt.grid(True, linestyle='--', alpha=0.7)
    plt.legend()
    plt.savefig('graph_free_space.png')
    print("Saved graph_free_space.png")

except FileNotFoundError:
    print(f"Error: Could not find file {file_path}")