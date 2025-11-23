#!/bin/bash

# Reset GLX
tt-smi -glx_reset; tt-smi -s > $HOME/results/device_map.json; sleep 300

# Remove csv result file if exist
mkdir -p $HOME/tt-metal-6u_test/generated/profiler/.logs
rm -f $HOME/tt-metal-6u_test/generated/profiler/.logs/test_all_ethernet_links_latency.csv

# Activate Python environment
# Run test with environment variables and log output
source $HOME/tt-metal-6u_test/python_env/bin/activate && \
  TT_METAL_HOME=$HOME/tt-metal-6u_test PYTHONPATH=$HOME/tt-metal-6u_test \
  time pytest $HOME/tt-metal-6u_test/tests/tt_metal/microbenchmarks/ethernet/test_all_ethernet_links_latency.py::test_erisc_latency_uni_dir \
  --num-iterations 10 2>&1 | tee $HOME/results/3_2_6_link_latency.log

# Check results
echo "Results:"
echo "--------------------------------------------------"
tail -n 20 $HOME/results/3_2_6_link_latency.log

# Check performance
awk -F',' '
BEGIN {
    # Create bus_id mapping from device_map.json
    cmd = "jq -r \".device_info | to_entries[] | \\\"\\(.key),\\(.value.board_info.bus_id)\\\"\" $HOME/results/device_map.json"
    while ((cmd | getline) > 0) {
        split($0, kv, ",")
        busid[kv[1]] = kv[2]
    }
    close(cmd)
}
NR>=6 && $2==1 && $8==1 && $9==16 {
    key=$3"->"$5"-"$7
    latency[key]+=$27
    cnt[key]++
    cable[key]=$7
    sender[key]=$3
    receiver[key]=$5
}
END {
    # Separate Internal and External links
    int_idx=0
    ext_idx=0
    for (k in latency) {
        avg_lat = latency[k]/cnt[k]

        if (cable[k] == "internal") {
            int_links[int_idx] = k
            int_lat_arr[int_idx] = avg_lat
            # Determine expected latency: 1290 if measured > 1290, otherwise 890
            int_exp_arr[int_idx] = (avg_lat > 1290) ? 1290 : 890
            int_idx++
        } else {
            ext_links[ext_idx] = k
            ext_lat_arr[ext_idx] = avg_lat
            ext_exp_arr[ext_idx] = 1690
            ext_idx++
        }
    }

    # Sort Internal links
    for (i=0; i<int_idx-1; i++) {
        for (j=i+1; j<int_idx; j++) {
            if (int_links[i] > int_links[j]) {
                tmp=int_links[i]; int_links[i]=int_links[j]; int_links[j]=tmp
                tmp=int_lat_arr[i]; int_lat_arr[i]=int_lat_arr[j]; int_lat_arr[j]=tmp
                tmp=int_exp_arr[i]; int_exp_arr[i]=int_exp_arr[j]; int_exp_arr[j]=tmp
            }
        }
    }

    # Sort External links
    for (i=0; i<ext_idx-1; i++) {
        for (j=i+1; j<ext_idx; j++) {
            if (ext_links[i] > ext_links[j]) {
                tmp=ext_links[i]; ext_links[i]=ext_links[j]; ext_links[j]=tmp
                tmp=ext_lat_arr[i]; ext_lat_arr[i]=ext_lat_arr[j]; ext_lat_arr[j]=tmp
                tmp=ext_exp_arr[i]; ext_exp_arr[i]=ext_exp_arr[j]; ext_exp_arr[j]=tmp
            }
        }
    }

    thresh_lat = 2000  # < 2us (2000ns) threshold

    # Print Internal links
    printf "=== Internal Links ===\n"
    for (i=0; i<int_idx; i++) {
        k = int_links[i]
        measured = int_lat_arr[i]
        expected = int_exp_arr[i]
        eff = expected / measured * 100
        result = (measured < thresh_lat) ? "PASS" : "FAIL"
        send_id = sender[k]
        recv_id = receiver[k]
        send_bus = busid[send_id]
        recv_bus = busid[recv_id]
        printf "Int: #%02d (%s) -> #%02d (%s): %.2f ns [exp=%.0f] (%.2f%%) %s\n",
               send_id, send_bus, recv_id, recv_bus, measured, expected, eff, result
    }

    # Print External links
    printf "\n=== External Links ===\n"
    for (i=0; i<ext_idx; i++) {
        k = ext_links[i]
        measured = ext_lat_arr[i]
        expected = ext_exp_arr[i]
        eff = expected / measured * 100
        result = (measured < thresh_lat) ? "PASS" : "FAIL"
        send_id = sender[k]
        recv_id = receiver[k]
        send_bus = busid[send_id]
        recv_bus = busid[recv_id]
        printf "Ext: #%02d (%s) -> #%02d (%s): %.2f ns [exp=%.0f] (%.2f%%) %s\n",
               send_id, send_bus, recv_id, recv_bus, measured, expected, eff, result
    }

    # Internal statistics
    int_n=0; int_pass=0
    for (i=0; i<int_idx; i++) {
        int_n++
        measured = int_lat_arr[i]
        eff = int_exp_arr[i] / measured * 100
        if (measured < thresh_lat) int_pass++
        int_s+=eff; int_sq+=eff*eff; int_ls+=log(eff);
        int_min=(i==0||eff<int_min)?eff:int_min;
        int_max=(i==0||eff>int_max)?eff:int_max;
        int_lat_min=(i==0||measured<int_lat_min)?measured:int_lat_min;
        int_lat_max=(i==0||measured>int_lat_max)?measured:int_lat_max;
    }

    # External statistics
    ext_n=0; ext_pass=0
    for (i=0; i<ext_idx; i++) {
        ext_n++
        measured = ext_lat_arr[i]
        eff = ext_exp_arr[i] / measured * 100
        if (measured < thresh_lat) ext_pass++
        ext_s+=eff; ext_sq+=eff*eff; ext_ls+=log(eff);
        ext_min=(i==0||eff<ext_min)?eff:ext_min;
        ext_max=(i==0||eff>ext_max)?eff:ext_max;
        ext_lat_min=(i==0||measured<ext_lat_min)?measured:ext_lat_min;
        ext_lat_max=(i==0||measured>ext_lat_max)?measured:ext_lat_max;
    }

    printf "\n=== Internal Links Summary (threshold < 2us) ===\n"
    int_avg=int_s/int_n; int_gm=exp(int_ls/int_n); int_sd=sqrt(int_sq/int_n-int_avg*int_avg);
    result=(int_lat_max < thresh_lat)?"PASS":"FAIL";
    printf "[n=%d latency min=%.2f max=%.2f] [eff min=%.2f%% max=%.2f%% avg=%.2f%% geomean=%.2f%% stdev=%.2f] [%d/%d PASS] %s\n",
           int_n, int_lat_min, int_lat_max, int_min, int_max, int_avg, int_gm, int_sd, int_pass, int_n, result

    printf "\n=== External Links Summary (threshold < 2us) ===\n"
    ext_avg=ext_s/ext_n; ext_gm=exp(ext_ls/ext_n); ext_sd=sqrt(ext_sq/ext_n-ext_avg*ext_avg);
    result=(ext_lat_max < thresh_lat)?"PASS":"FAIL";
    printf "[n=%d latency min=%.2f max=%.2f] [eff min=%.2f%% max=%.2f%% avg=%.2f%% geomean=%.2f%% stdev=%.2f] [%d/%d PASS] %s\n",
           ext_n, ext_lat_min, ext_lat_max, ext_min, ext_max, ext_avg, ext_gm, ext_sd, ext_pass, ext_n, result
}' $HOME/tt-metal-6u_test/generated/profiler/.logs/test_all_ethernet_links_latency.csv