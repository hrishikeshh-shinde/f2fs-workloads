#!/bin/bash
BEFORE=$(awk '{print $7}' /tmp/stat_before.txt)
AFTER=$(awk '{print $7}' /tmp/stat_after.txt)
LOGICAL=$(cat /tmp/logical.txt)
DELTA=$((AFTER - BEFORE))
PHYSICAL=$((DELTA * 512))
WAF=$(echo "scale=3; $PHYSICAL / $LOGICAL" | bc)
echo "WAF: $WAF (Physical: ${PHYSICAL}, Logical: ${LOGICAL})"