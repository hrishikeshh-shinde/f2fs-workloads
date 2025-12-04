#!/bin/bash
echo "GC events: $(grep -c 'f2fs_gc_begin' /sys/kernel/debug/tracing/trace 2>/dev/null || echo 0)"