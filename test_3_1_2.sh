#!/bin/bash

# Reset GLX
tt-smi -glx_reset; tt-smi -s > $HOME/results/device_map.json; sleep 300

# Run test with environment variables and log output
TT_METAL_HOME=$HOME/tt-metal-6u_test PYTHONPATH=$HOME/tt-metal-6u_test \
  time $HOME/tt-metal-6u_test/build/test/tt_metal/tt_fabric/test_system_health --system-topology TORUS_2D 2>&1 | \
  tee $HOME/results/3_1_2_external_connectivity.log

# Check results
echo "Results:"
echo "--------------------------------------------------"
grep "Cluster." $HOME/results/3_1_2_external_connectivity.log