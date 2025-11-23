#!/bin/bash

# Reset GLX
tt-smi -glx_reset; tt-smi -s > $HOME/results/device_map.json; sleep 300

# Remove csv result file if exist
mkdir -p $HOME/tt-metal-6u_test/generated/profiler/.logs
rm -f $HOME/tt-metal-6u_test/generated/profiler/.logs/moreh_test_pcie_transfer.csv

# Activate Python environment
# Run test with environment variables and log output
source $HOME/tt-metal-6u_test/python_env/bin/activate && \
    TT_METAL_HOME=$HOME/tt-metal-6u_test PYTHONPATH=$HOME/tt-metal-6u_test \
    time pytest $HOME/tt-metal-6u_test/tests/scripts/test_moreh_microbenchmark.py::test_pcie_transfer 2>&1 | \
    tee $HOME/results/3_2_4_pcie_bandwidth.log

# Check results
echo "Results:"
echo "--------------------------------------------------"
tail -n 20 $HOME/results/3_2_4_pcie_bandwidth.log

# Check performance
# Extract x8 and x1 device lists from device_map.json
x8_devices=$(jq -r '.device_info | to_entries[] | select(.value.board_info.pcie_width == "8") | .key' $HOME/results/device_map.json | tr '\n' ',' | sed 's/,$//')
x1_devices=$(jq -r '.device_info | to_entries[] | select(.value.board_info.pcie_width == "1") | .key' $HOME/results/device_map.json | tr '\n' ',' | sed 's/,$//')

# Analyze H2D x8 transfers
echo "=== H2D x8 (threshold=9GB/s) ==="
awk -F',' -v devs="$x8_devices" -v thresh=9 '
BEGIN {
    # Split device list into array
    split(devs, arr, ",")
}
NR>1 && $2=="DRAM" && $3==536870912 {
    # Check if current device is in x8 list
    for (i in arr) {
        if ($1==arr[i]) {
            # Accumulate statistics for H2D bandwidth (field 4)
            s+=$4; sq+=$4*$4; ls+=log($4); n++
            min=(n==1||$4<min)?$4:min
            max=(n==1||$4>max)?$4:max
        }
    }
}
END {
    if (n>0) {
        # Calculate statistics
        avg=s/n; gm=exp(ls/n); sd=sqrt(sq/n-avg*avg)
        result=(min>=thresh)?"PASS":"FAIL"
        printf "[n=%d min=%.2f max=%.2f avg=%.2f geomean=%.2f stdev=%.2f] %s\n", n, min, max, avg, gm, sd, result
    }
}' $HOME/tt-metal-6u_test/generated/profiler/.logs/moreh_test_pcie_transfer.csv

# Analyze D2H x8 transfers
echo "=== D2H x8 (threshold=9GB/s) ==="
awk -F',' -v devs="$x8_devices" -v thresh=9 '
BEGIN {
    split(devs, arr, ",")
}
NR>1 && $2=="DRAM" && $3==536870912 {
    for (i in arr) {
        if ($1==arr[i]) {
            # Accumulate statistics for D2H bandwidth (field 5)
            s+=$5; sq+=$5*$5; ls+=log($5); n++
            min=(n==1||$5<min)?$5:min
            max=(n==1||$5>max)?$5:max
        }
    }
}
END {
    if (n>0) {
        avg=s/n; gm=exp(ls/n); sd=sqrt(sq/n-avg*avg)
        result=(min>=thresh)?"PASS":"FAIL"
        printf "[n=%d min=%.2f max=%.2f avg=%.2f geomean=%.2f stdev=%.2f] %s\n", n, min, max, avg, gm, sd, result
    }
}' $HOME/tt-metal-6u_test/generated/profiler/.logs/moreh_test_pcie_transfer.csv

# Analyze H2D x1 transfers
echo "=== H2D x1 (threshold=1.6GB/s) ==="
awk -F',' -v devs="$x1_devices" -v thresh=1.6 '
BEGIN {
    split(devs, arr, ",")
}
NR>1 && $2=="DRAM" && $3==536870912 {
    for (i in arr) {
        if ($1==arr[i]) {
            # Accumulate statistics for H2D bandwidth (field 4)
            s+=$4; sq+=$4*$4; ls+=log($4); n++
            min=(n==1||$4<min)?$4:min
            max=(n==1||$4>max)?$4:max
        }
    }
}
END {
    if (n>0) {
        avg=s/n; gm=exp(ls/n); sd=sqrt(sq/n-avg*avg)
        result=(min>=thresh)?"PASS":"FAIL"
        printf "[n=%d min=%.2f max=%.2f avg=%.2f geomean=%.2f stdev=%.2f] %s\n", n, min, max, avg, gm, sd, result
    }
}' $HOME/tt-metal-6u_test/generated/profiler/.logs/moreh_test_pcie_transfer.csv

# Analyze D2H x1 transfers
echo "=== D2H x1 (threshold=1.6GB/s) ==="
awk -F',' -v devs="$x1_devices" -v thresh=1.6 '
BEGIN {
    split(devs, arr, ",")
}
NR>1 && $2=="DRAM" && $3==536870912 {
    for (i in arr) {
        if ($1==arr[i]) {
            # Accumulate statistics for D2H bandwidth (field 5)
            s+=$5; sq+=$5*$5; ls+=log($5); n++
            min=(n==1||$5<min)?$5:min
            max=(n==1||$5>max)?$5:max
        }
    }
}
END {
    if (n>0) {
        avg=s/n; gm=exp(ls/n); sd=sqrt(sq/n-avg*avg)
        result=(min>=thresh)?"PASS":"FAIL"
        printf "[n=%d min=%.2f max=%.2f avg=%.2f geomean=%.2f stdev=%.2f] %s\n", n, min, max, avg, gm, sd, result
    }
}' $HOME/tt-metal-6u_test/generated/profiler/.logs/moreh_test_pcie_transfer.csv