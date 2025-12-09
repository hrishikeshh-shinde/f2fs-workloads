import pandas as pd
import matplotlib.pyplot as plt
import sys
import numpy as np

# Usage: python3 plot_zombie_fast.py femu_stats.csv "Title_Here"
if len(sys.argv) < 2:
    print("Usage: python3 plot_zombie_fast.py <csv_file> [title]")
    sys.exit(1)

file_path = sys.argv[1]
title_text = sys.argv[2] if len(sys.argv) > 2 else "Zombie Curve"

print(f"Reading {file_path}...")
df = pd.read_csv(file_path)

timestamps = sorted(df['sample'].unique())
zombie_pct = []
time_points = []

print(f"Processing {len(timestamps)} samples...")

for ts in timestamps:
    snapshot = df[df['sample'] == ts]
    
    # --- YOUR OPTIMIZATION (Restored) ---
    # This groups duplicates by block address and takes the last one.
    # This is why your script was fast and mine was slow.
    latest = snapshot.groupby(['ch','lun','pl','blk']).last().reset_index()
    
    # Active = Any block that is not completely empty
    active = latest[(latest['vpc'] > 0) | (latest['ipc'] > 0)].copy()
    
    if len(active) == 0:
        zombie_pct.append(0)
    else:
        # Invalid Ratio (ir)
        active['ir'] = active['ipc'] / (active['vpc'] + active['ipc'])
        
        # Zombie Definition: 30% - 70% Invalid
        zombie = active[(active['ir'] >= 0.3) & (active['ir'] <= 0.7)]
        
        zombie_pct.append(len(zombie)/len(active)*100)
    
    time_points.append(ts)

# --- PLOTTING (Zombie Only) ---
plt.figure(figsize=(12, 7))

# Plot the Curve
plt.plot(range(len(time_points)), zombie_pct, color='orange', linewidth=3, label='Zombie Segments (30-70% Invalid)')
plt.fill_between(range(len(time_points)), zombie_pct, color='orange', alpha=0.2)

# --- ANNOTATIONS ---
# 1. Peak (GC Saturation)
if len(zombie_pct) > 0:
    peak_val = max(zombie_pct)
    peak_idx = zombie_pct.index(peak_val)
    
    plt.annotate(f'GC Saturation\n(Peak: {peak_val:.1f}%)', 
                 xy=(peak_idx, peak_val), xytext=(peak_idx, peak_val + 10),
                 arrowprops=dict(facecolor='red', shrink=0.05),
                 bbox=dict(boxstyle='round', facecolor='white', alpha=0.8), color='red')

    # 2. The Drop (Compaction Success)
    # Find point after peak where it drops low
    for i in range(peak_idx, len(zombie_pct)):
        if zombie_pct[i] < (peak_val / 4): # Drops to 25% of peak
            plt.annotate('Compaction Success\n(Zombies Removed)', 
                         xy=(i, zombie_pct[i]), xytext=(i - 10, zombie_pct[i] + 15),
                         arrowprops=dict(facecolor='blue', shrink=0.05),
                         bbox=dict(boxstyle='round', facecolor='white', alpha=0.8), color='blue')
            break

plt.xlabel('Time (Sample Points)', fontsize=12)
plt.ylabel('Percentage of Disk (%)', fontsize=12)
plt.title(f'{title_text}: Evolution of Zombie Segments', fontsize=14)
plt.ylim(0, 100)
plt.grid(True, linestyle='--', alpha=0.5)
plt.legend(loc='upper right')

output_file = "zombie_curve_fast.png"
plt.tight_layout()
plt.savefig(output_file, dpi=300)
print(f"Graph saved to: {output_file}")