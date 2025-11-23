#!/bin/bash

# Reset GLX
tt-smi -glx_reset; tt-smi -s > $HOME/results/device_map.json; sleep 300

# Run test with environment variables and log output
TT_METAL_HOME=$HOME/tt-metal-6u_test PYTHONPATH=$HOME/tt-metal-6u_test \
    TT_METAL_SKIP_ETH_CORES_WITH_RETRAIN=1 \
    time $HOME/tt-metal-6u_test/build/test/tt_metal/unit_tests_dispatch \
    --gtest_filter="CommandQueueSingleCardFixture.*" | \
    tee $HOME/results/3_1_3_a_chip_functionality.log

# Check results
echo "Results:"
echo "--------------------------------------------------"
grep "CommandQueueSingleCardFixture." $HOME/results/3_1_3_*.log