#!/bin/bash

# Reset GLX
tt-smi -glx_reset; tt-smi -s > $HOME/results/device_map.json; sleep 300

# Remove csv result file if exist
mkdir -p $HOME/tt-metal-6u_test/generated/profiler/.logs
rm -f $HOME/tt-metal-6u_test/generated/profiler/.logs/moreh_test_dram_read_all_core.csv

# Activate Python environment
# Run test with environment variables and log output
source $HOME/tt-metal-6u_test/python_env/bin/activate && \
  TT_METAL_HOME=$HOME/tt-metal-6u_test PYTHONPATH=$HOME/tt-metal-6u_test \
  time pytest $HOME/tt-metal-6u_test/tests/scripts/test_moreh_microbenchmark.py::test_dram_read_all_core 2>&1 | \
  tee $HOME/results/3_2_2_dram_bandwidth.log

# Check results
echo "Results:"
echo "--------------------------------------------------"
tail -n 20 $HOME/results/3_2_2_dram_bandwidth.log

# Check performance
for size_bw in "3145728:336" "6291456:336" "12582912:336" "25165824:336" "50331648:336" "100663296:336"; do
    size=${size_bw%:*}
    theo=${size_bw#*:}

    awk -F',' -v sz="$size" -v theo="$theo" '
    NR>1 && $2==sz {
        s+=$NF
        sq+=$NF*$NF
        ls+=log($NF)
        n++
        min=(n==1||$NF<min)?$NF:min
        max=(n==1||$NF>max)?$NF:max
    }
    END {
        if (n>0) {
            avg=s/n
            gm=exp(ls/n)
            sd=sqrt(sq/n-avg*avg)
            printf "%s [size=%d theo=%.0f]: [n=%d min=%.2f(%.1f%%) max=%.2f(%.1f%%) avg=%.2f(%.1f%%) geomean=%.2f(%.1f%%) stdev=%.2f]\n",
                   FILENAME, sz, theo, n, min, min/theo*100, max, max/theo*100, avg, avg/theo*100, gm, gm/theo*100, sd
        }
    }' $HOME/tt-metal-6u_test/generated/profiler/.logs/moreh_test_dram_read_all_core.csv
done