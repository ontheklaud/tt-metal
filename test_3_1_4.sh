#!/bin/bash

# Reset GLX
tt-smi -glx_reset; tt-smi -s > $HOME/results/device_map.json; sleep 120

# Run test with environment variables and log output
TT_METAL_HOME=$HOME/tt-metal-6u_test PYTHONPATH=$HOME/tt-metal-6u_test \
    TT_METAL_SLOW_DISPATCH_MODE=1 time $HOME/tt-metal-6u_test/build/test/tt_metal/tt_fabric/fabric_unit_tests \
    --gtest_filter="Fabric2D*Fixture.*" 2>&1 | \
    tee $HOME/results/3_1_4_communication_functionality.log

# Check results
echo "Results:"
echo "--------------------------------------------------"
grep -E "(Fabric2DFixture|Fabric2DDynamicFixture)" $HOME/results/3_1_4_communication_functionality.log