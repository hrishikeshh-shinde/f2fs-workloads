import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

df = pd.read_csv('/users/proteet/f2fs-workloads/suppporting_experiments/bpftrace_output2.csv')

page_idx = 492
# pages_in_block = [block_idx * pages_per_blk + i for i in range(pages_per_blk)]
new_df = df[df['page_index'] == page_idx].sort_values(by='timestamp')

# Create the scatter plot
plt.scatter(new_df['timestamp']/1000, new_df['death_time_ms'], s=20)

# Add labels and title (optional)
plt.xlabel("Time (s)")
plt.ylabel("Death Time (ms)")
plt.title("Variation of Death Times for a chunk (SQLite Journal; chunk size=128 pages)", {'fontsize': 11})
plt.yscale('log', base=10)

# Display the plot
plt.savefig("temporal_locality_blocks.png")