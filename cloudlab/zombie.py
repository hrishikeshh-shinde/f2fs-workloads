import pandas as pd
import matplotlib.pyplot as plt
import sys

df = pd.read_csv(sys.argv[1])

# Get unique timestamps
timestamps = sorted(df['sample'].unique())

zombie_pct = []
hot_pct = []
cold_pct = []
active_count = []

for ts in timestamps:
    snapshot = df[df['sample'] == ts]
    latest = snapshot.groupby(['ch','lun','pl','blk']).last().reset_index()
    active = latest[(latest['vpc'] > 0) | (latest['ipc'] > 0)].copy()
    
    if len(active) == 0:
        continue
    
    active['ir'] = active['ipc'] / (active['vpc'] + active['ipc'])
    
    hot = active[active['ir'] > 0.7]
    zombie = active[(active['ir'] >= 0.3) & (active['ir'] <= 0.7)]
    cold = active[active['ir'] < 0.3]
    
    zombie_pct.append(len(zombie)/len(active)*100)
    hot_pct.append(len(hot)/len(active)*100)
    cold_pct.append(len(cold)/len(active)*100)
    active_count.append(len(active))

# Plot
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 10))

# Temporal evolution
ax1.plot(range(len(timestamps)), cold_pct, 'b-', linewidth=2, label='Cold (<30% invalid)')
ax1.plot(range(len(timestamps)), zombie_pct, 'orange', linewidth=3, label='Zombie (30-70% invalid)')
ax1.plot(range(len(timestamps)), hot_pct, 'r-', linewidth=2, label='Hot (>70% invalid)')
ax1.fill_between(range(len(timestamps)), zombie_pct, alpha=0.3, color='orange')
ax1.set_xlabel('Time (sample points)', fontsize=12)
ax1.set_ylabel('Block Percentage (%)', fontsize=12)
ax1.set_title(f'{sys.argv[2]}: Temporal Evolution of Block States', fontsize=14)
ax1.legend(fontsize=11, loc='best')
ax1.grid(True, alpha=0.3)
ax1.set_ylim([0, 100])

# Active blocks growth
ax2.plot(range(len(timestamps)), active_count, 'g-', linewidth=2)
ax2.set_xlabel('Time (sample points)', fontsize=12)
ax2.set_ylabel('Active Blocks', fontsize=12)
ax2.set_title('Block Usage Over Time', fontsize=14)
ax2.grid(True, alpha=0.3)

plt.tight_layout()
plt.savefig(f'{sys.argv[2]}_temporal.png', dpi=300)
print(f"Saved: {sys.argv[2]}_temporal.png")
print(f"Peak zombies: {max(zombie_pct):.1f}% at sample {timestamps[zombie_pct.index(max(zombie_pct))]}")
