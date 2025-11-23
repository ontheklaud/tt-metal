#!/bin/bash

# Reset GLX
tt-smi -glx_reset; tt-smi -s > $HOME/results/device_map.json; sleep 300

# Remove csv result file if exist
mkdir -p $HOME/tt-metal-6u_test/generated/profiler/.logs
rm -f $HOME/tt-metal-6u_test/generated/profiler/.logs/test_all_ethernet_links_bandwidth.csv

# Activate Python environment
# Run test with environment variables and log output
source $HOME/tt-metal-6u_test/python_env/bin/activate && \
  TT_METAL_HOME=$HOME/tt-metal-6u_test PYTHONPATH=$HOME/tt-metal-6u_test \
  time pytest $HOME/tt-metal-6u_test/tests/tt_metal/microbenchmarks/ethernet/test_all_ethernet_links_bandwidth.py::test_erisc_bw_uni_dir \
  --num-iterations 10 2>&1 | tee $HOME/results/3_2_5_link_bandwidth.log

# Check results
echo "Results:"
echo "--------------------------------------------------"
tail -n 20 $HOME/results/3_2_5_link_bandwidth.log

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
NR>=6 && $2==1 && $8==256 && $9==8192 {
    key=$3"->"$5"-"$7
    bw[key]+=$27
    cnt[key]++
    cable[key]=$7
    sender[key]=$3
    receiver[key]=$5
}
END {
    theo=12.5
    thresh=11.875

    # Separate Internal and External links
    int_idx=0
    ext_idx=0
    for (k in bw) {
        avg_bw = bw[k]/cnt[k]

        if (cable[k] == "internal") {
            int_links[int_idx] = k
            int_bw_arr[int_idx] = avg_bw
            int_idx++
        } else {
            ext_links[ext_idx] = k
            ext_bw_arr[ext_idx] = avg_bw
            ext_idx++
        }
    }

    # Sort Internal links
    for (i=0; i<int_idx-1; i++) {
        for (j=i+1; j<int_idx; j++) {
            if (int_links[i] > int_links[j]) {
                tmp=int_links[i]; int_links[i]=int_links[j]; int_links[j]=tmp
                tmp=int_bw_arr[i]; int_bw_arr[i]=int_bw_arr[j]; int_bw_arr[j]=tmp
            }
        }
    }

    # Sort External links
    for (i=0; i<ext_idx-1; i++) {
        for (j=i+1; j<ext_idx; j++) {
            if (ext_links[i] > ext_links[j]) {
                tmp=ext_links[i]; ext_links[i]=ext_links[j]; ext_links[j]=tmp
                tmp=ext_bw_arr[i]; ext_bw_arr[i]=ext_bw_arr[j]; ext_bw_arr[j]=tmp
            }
        }
    }

    # Print Internal links
    printf "=== Internal Links ===\n"
    for (i=0; i<int_idx; i++) {
        k = int_links[i]
        avg_bw = int_bw_arr[i]
        eff = avg_bw/theo*100
        result = (avg_bw >= thresh) ? "PASS" : "FAIL"
        send_id = sender[k]
        recv_id = receiver[k]
        send_bus = busid[send_id]
        recv_bus = busid[recv_id]
        printf "Int: #%02d (%s) -> #%02d (%s): %.2f GB/s (%.2f%%) %s\n", send_id, send_bus, recv_id, recv_bus, avg_bw, eff, result
    }

    # Print External links
    printf "\n=== External Links ===\n"
    for (i=0; i<ext_idx; i++) {
        k = ext_links[i]
        avg_bw = ext_bw_arr[i]
        eff = avg_bw/theo*100
        result = (avg_bw >= thresh) ? "PASS" : "FAIL"
        send_id = sender[k]
        recv_id = receiver[k]
        send_bus = busid[send_id]
        recv_bus = busid[recv_id]
        printf "Ext: #%02d (%s) -> #%02d (%s): %.2f GB/s (%.2f%%) %s\n", send_id, send_bus, recv_id, recv_bus, avg_bw, eff, result
    }

    # Internal statistics
    int_n=0
    for (i=0; i<int_idx; i++) {
        int_bw[++int_n] = int_bw_arr[i]
        int_s+=int_bw_arr[i]; int_sq+=int_bw_arr[i]*int_bw_arr[i]; int_ls+=log(int_bw_arr[i]);
        int_min=(i==0||int_bw_arr[i]<int_min)?int_bw_arr[i]:int_min;
        int_max=(i==0||int_bw_arr[i]>int_max)?int_bw_arr[i]:int_max;
    }

    # External statistics
    ext_n=0
    for (i=0; i<ext_idx; i++) {
        ext_bw[++ext_n] = ext_bw_arr[i]
        ext_s+=ext_bw_arr[i]; ext_sq+=ext_bw_arr[i]*ext_bw_arr[i]; ext_ls+=log(ext_bw_arr[i]);
        ext_min=(i==0||ext_bw_arr[i]<ext_min)?ext_bw_arr[i]:ext_min;
        ext_max=(i==0||ext_bw_arr[i]>ext_max)?ext_bw_arr[i]:ext_max;
    }

    printf "\n=== Internal Links Summary (theo=12.5GB/s, threshold=11.875GB/s) ===\n"
    int_avg=int_s/int_n; int_gm=exp(int_ls/int_n); int_sd=sqrt(int_sq/int_n-int_avg*int_avg);
    result=(int_min>=thresh)?"PASS":"FAIL";
    printf "[n=%d min=%.2f(%.2f%%) max=%.2f(%.2f%%) avg=%.2f(%.2f%%) geomean=%.2f(%.2f%%) stdev=%.2f] %s\n",
           int_n, int_min, int_min/theo*100, int_max, int_max/theo*100, int_avg, int_avg/theo*100, int_gm, int_gm/theo*100, int_sd, result

    printf "\n=== External Links Summary (theo=12.5GB/s, threshold=11.875GB/s) ===\n"
    ext_avg=ext_s/ext_n; ext_gm=exp(ext_ls/ext_n); ext_sd=sqrt(ext_sq/ext_n-ext_avg*ext_avg);
    result=(ext_min>=thresh)?"PASS":"FAIL";
    printf "[n=%d min=%.2f(%.2f%%) max=%.2f(%.2f%%) avg=%.2f(%.2f%%) geomean=%.2f(%.2f%%) stdev=%.2f] %s\n",
           ext_n, ext_min, ext_min/theo*100, ext_max, ext_max/theo*100, ext_avg, ext_avg/theo*100, ext_gm, ext_gm/theo*100, ext_sd, result
}' $HOME/tt-metal-6u_test/generated/profiler/.logs/test_all_ethernet_links_bandwidth.csv