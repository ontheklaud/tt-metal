#!/bin/bash

# Reset GLX
tt-smi -glx_reset; tt-smi -s > $HOME/results/device_map.json; sleep 300

# Remove csv result file if exist
mkdir -p $HOME/tt-metal-6u_test/generated/profiler/.logs
rm -f $HOME/tt-metal-6u_test/generated/profiler/.logs/moreh_test_noc_adjacent.csv

# Activate Python environment
# Run test with environment variables and log output
source $HOME/tt-metal-6u_test/python_env/bin/activate && \
    TT_METAL_HOME=$HOME/tt-metal-6u_test PYTHONPATH=$HOME/tt-metal-6u_test \
    time pytest $HOME/tt-metal-6u_test/tests/scripts/test_moreh_microbenchmark.py::test_noc_adjacent 2>&1 | \
    tee $HOME/results/3_2_3_b_noc_adjacent.log

# Check results
echo "Results:"
echo "--------------------------------------------------"
tail -n 20 $HOME/results/3_2_3_b_noc_adjacent.log

# Check performance
awk -F',' '
NR>1 && $5==32 {
    key=$6","$7","$8
    bw[key]+=$10
    cnt[key]++

    if (bw_min[key]=="" || $10<bw_min[key]) bw_min[key]=$10
    if (bw_max[key]=="" || $10>bw_max[key]) bw_max[key]=$10
}
END {
    theo = 32.0
    thresh = 80.0  # 80% efficiency

    # Combinations
    combos[1]="NOC_RISCV_0,X_PLUS_DIR,WRITE"
    combos[2]="NOC_RISCV_0,Y_MINUS_DIR,READ"
    combos[3]="NOC_RISCV_0,X_MINUS_DIR,READ"
    combos[4]="NOC_RISCV_0,Y_PLUS_DIR,WRITE"
    combos[5]="NOC_RISCV_1,X_PLUS_DIR,READ"
    combos[6]="NOC_RISCV_1,Y_MINUS_DIR,WRITE"
    combos[7]="NOC_RISCV_1,X_MINUS_DIR,WRITE"
    combos[8]="NOC_RISCV_1,Y_PLUS_DIR,READ"

    printf "=== NOC Adjacent Bandwidth (tiles-per-transfer=32, theo=32 B/cc) ===\n"

    for (i=1; i<=8; i++) {
        k = combos[i]
        if (cnt[k] > 0) {
            avg = bw[k]/cnt[k]
            min_eff = bw_min[k]/theo*100
            max_eff = bw_max[k]/theo*100
            avg_eff = avg/theo*100
            result = (min_eff >= thresh) ? "PASS" : "FAIL"
            printf "%s: [n=%d min=%.3f(%.2f%%) max=%.3f(%.2f%%) avg=%.3f(%.2f%%)] %s\n",
                   k, cnt[k], bw_min[k], min_eff, bw_max[k], max_eff, avg, avg_eff, result
        } else {
            printf "%s: [NO DATA]\n", k
        }
    }
}' $HOME/tt-metal-6u_test/generated/profiler/.logs/moreh_test_noc_adjacent.csv