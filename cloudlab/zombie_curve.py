import pandas as pd, numpy as np, matplotlib.pyplot as plt, sys

df = pd.read_csv(sys.argv[1])
latest = df.groupby(['ch','lun','pl','blk']).last().reset_index()
active = latest[(latest['vpc'] > 0) | (latest['ipc'] > 0)].copy()
active['invalid_ratio'] = active['ipc'] / (active['vpc'] + active['ipc'])
active['invalid_ratio'] = active['invalid_ratio'].fillna(0)
zombie = active[(active['invalid_ratio'] >= 0.3) & (active['invalid_ratio'] <= 0.7)]

print(f"Active blocks: {len(active)}")
print(f"Zombie blocks: {len(zombie)}")
print(f"Zombie %: {len(zombie)/len(active)*100:.1f}%")

plt.figure(figsize=(8,5))
plt.hist(active['invalid_ratio'], bins=50, edgecolor='black', alpha=0.7)
plt.axvline(0.3, color='blue', linestyle='--')
plt.axvline(0.7, color='red', linestyle='--')
plt.xlabel('Invalid Page Ratio')
plt.ylabel('Block Count')
plt.title(f'{sys.argv[2]}: {len(zombie)} Zombie Blocks ({len(zombie)/len(active)*100:.1f}%)')
plt.savefig(f'{sys.argv[2]}_zombie.png', dpi=300)
print(f"Saved: {sys.argv[2]}_zombie.png")

# Save data
active[['invalid_ratio']].to_csv(f'{sys.argv[2]}_zombie_data.csv', index=False)