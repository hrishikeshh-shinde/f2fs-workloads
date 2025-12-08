import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

df = pd.read_csv('/users/proteet/f2fs-workloads/suppporting_experiments/bpftrace_output.csv')

# Create the scatter plot
plt.scatter(df['page_index'], df['death_time_ms'], s=10)

# Add labels and title (optional)
plt.xlabel("Logical File Offset")
plt.ylabel("Death Time (ms)")
plt.title("Distribution of Death Times (SQLite Journal)")

# Display the plot
plt.savefig("all_death_times_plot.png")