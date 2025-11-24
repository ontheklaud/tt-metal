#!/bin/bash

# SPDX-FileCopyrightText: © 2023 Tenstorrent AI ULC
#
# SPDX-License-Identifier: Apache-2.0

# Unified test runner for microbenchmark validation tests
# Usage: ./run_test_microbench.sh [test_name]
#   test_name: 3_2_2, 3_2_3, 3_2_4, 3_2_5, 3_2_6

set -e

TEST_NAME=$1

if [ -z "$TEST_NAME" ]; then
    echo "Usage: $0 [test_name]"
    echo "  test_name options:"
    echo "    3_2_2 - DRAM Bandwidth Test"
    echo "    3_2_3 - NOC Adjacent Bandwidth Test"
    echo "    3_2_4 - PCIe Transfer Bandwidth Test"
    echo "    3_2_5 - Ethernet Link Bandwidth Test"
    echo "    3_2_6 - Ethernet Link Latency Test"
    exit 1
fi

# Validate test_name
if [[ ! "$TEST_NAME" =~ ^3_2_[23456]$ ]]; then
    echo "Error: Invalid test_name '$TEST_NAME'. Must be 3_2_2, 3_2_3, 3_2_4, 3_2_5, or 3_2_6."
    exit 1
fi

# Common setup
echo "=========================================="
echo "Running Test ${TEST_NAME}"
echo "=========================================="

# Reset GLX
echo "Resetting GLX and capturing device map..."
tt-smi -glx_reset
tt-smi -s > $HOME/results/device_map.json
sleep 300

# Activate Python environment
source $HOME/tt-metal-6u_test/python_env/bin/activate
export TT_METAL_HOME=$HOME/tt-metal-6u_test
export PYTHONPATH=$HOME/tt-metal-6u_test

# Create output directory
mkdir -p $HOME/tt-metal-6u_test/generated/profiler/.logs
mkdir -p $HOME/results

# Switch based on test_name
case $TEST_NAME in
    3_2_2)
        # DRAM Bandwidth Test
        TEST_FUNCTION="test_dram_read_all_core"
        CSV_FILE="moreh_test_dram_read_all_core.csv"
        LOG_FILE="3_2_2_dram_bandwidth.log"

        echo "Removing old CSV results..."
        rm -f $HOME/tt-metal-6u_test/generated/profiler/.logs/$CSV_FILE

        echo "Running DRAM Bandwidth Test..."
        time pytest $HOME/tt-metal-6u_test/tests/scripts/run_test_microbench.py::$TEST_FUNCTION 2>&1 | \
            tee $HOME/results/$LOG_FILE

        echo ""
        echo "Results:"
        echo "--------------------------------------------------"
        tail -n 20 $HOME/results/$LOG_FILE

        echo ""
        echo "Performance Analysis:"
        echo "--------------------------------------------------"
        # Run Python analysis
        python3 -c "
import sys
sys.path.insert(0, '$HOME/tt-metal-6u_test/tests/scripts')
from run_test_microbench import analyze_dram_bandwidth_results_on_completion
analyze_dram_bandwidth_results_on_completion()
"
        ;;

    3_2_3)
        # NOC Adjacent Bandwidth Test
        TEST_FUNCTION="test_noc_adjacent"
        CSV_FILE="moreh_test_noc_adjacent.csv"
        LOG_FILE="3_2_3_noc_adjacent.log"

        echo "Removing old CSV results..."
        rm -f $HOME/tt-metal-6u_test/generated/profiler/.logs/$CSV_FILE

        echo "Running NOC Adjacent Bandwidth Test..."
        time pytest $HOME/tt-metal-6u_test/tests/scripts/run_test_microbench.py::$TEST_FUNCTION 2>&1 | \
            tee $HOME/results/$LOG_FILE

        echo ""
        echo "Results:"
        echo "--------------------------------------------------"
        tail -n 20 $HOME/results/$LOG_FILE

        echo ""
        echo "Performance Analysis:"
        echo "--------------------------------------------------"
        # Run Python analysis
        python3 -c "
import sys
sys.path.insert(0, '$HOME/tt-metal-6u_test/tests/scripts')
from run_test_microbench import analyze_noc_adjacent_results_on_completion
analyze_noc_adjacent_results_on_completion()
"
        ;;

    3_2_4)
        # PCIe Transfer Bandwidth Test
        TEST_FUNCTION="test_pcie_transfer"
        CSV_FILE="moreh_test_pcie_transfer.csv"
        LOG_FILE="3_2_4_pcie_bandwidth.log"

        echo "Removing old CSV results..."
        rm -f $HOME/tt-metal-6u_test/generated/profiler/.logs/$CSV_FILE

        echo "Running PCIe Transfer Bandwidth Test..."
        time pytest $HOME/tt-metal-6u_test/tests/scripts/run_test_microbench.py::$TEST_FUNCTION 2>&1 | \
            tee $HOME/results/$LOG_FILE

        echo ""
        echo "Results:"
        echo "--------------------------------------------------"
        tail -n 20 $HOME/results/$LOG_FILE

        echo ""
        echo "Performance Analysis:"
        echo "--------------------------------------------------"
        # Run Python analysis
        python3 -c "
import sys
sys.path.insert(0, '$HOME/tt-metal-6u_test/tests/scripts')
from run_test_microbench import analyze_pcie_transfer_results_on_completion
analyze_pcie_transfer_results_on_completion('$HOME/results/device_map.json')
"
        ;;

    3_2_5)
        # Ethernet Link Bandwidth Test
        CSV_FILE="test_all_ethernet_links_bandwidth.csv"
        LOG_FILE="3_2_5_link_bandwidth.log"

        echo "Removing old CSV results..."
        rm -f $HOME/tt-metal-6u_test/generated/profiler/.logs/$CSV_FILE

        echo "Running Ethernet Link Bandwidth Test..."
        time pytest $HOME/tt-metal-6u_test/tests/tt_metal/microbenchmarks/ethernet/test_all_ethernet_links_bandwidth.py::test_erisc_bw_uni_dir \
            --num-iterations 10 2>&1 | tee $HOME/results/$LOG_FILE

        echo ""
        echo "Results:"
        echo "--------------------------------------------------"
        tail -n 20 $HOME/results/$LOG_FILE

        echo ""
        echo "Performance Analysis:"
        echo "--------------------------------------------------"
        # Run Python analysis
        python3 -c "
import sys
sys.path.insert(0, '$HOME/tt-metal-6u_test/tests/scripts')
from run_test_microbench import analyze_ethernet_bandwidth_results_on_completion
analyze_ethernet_bandwidth_results_on_completion('$HOME/results/device_map.json')
"
        ;;

    3_2_6)
        # Ethernet Link Latency Test
        CSV_FILE="test_all_ethernet_links_latency.csv"
        LOG_FILE="3_2_6_link_latency.log"

        echo "Removing old CSV results..."
        rm -f $HOME/tt-metal-6u_test/generated/profiler/.logs/$CSV_FILE

        echo "Running Ethernet Link Latency Test..."
        time pytest $HOME/tt-metal-6u_test/tests/tt_metal/microbenchmarks/ethernet/test_all_ethernet_links_latency.py::test_erisc_latency_uni_dir \
            --num-iterations 10 2>&1 | tee $HOME/results/$LOG_FILE

        echo ""
        echo "Results:"
        echo "--------------------------------------------------"
        tail -n 20 $HOME/results/$LOG_FILE

        echo ""
        echo "Performance Analysis:"
        echo "--------------------------------------------------"
        # Run Python analysis
        python3 -c "
import sys
sys.path.insert(0, '$HOME/tt-metal-6u_test/tests/scripts')
from run_test_microbench import analyze_ethernet_latency_results_on_completion
analyze_ethernet_latency_results_on_completion('$HOME/results/device_map.json')
"
        ;;

    *)
        echo "Error: Invalid test_name '$TEST_NAME'"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "Test ${TEST_NAME} completed"
echo "=========================================="
