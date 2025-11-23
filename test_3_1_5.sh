#!/bin/bash

# Reset GLX
tt-smi -glx_reset; tt-smi -s > $HOME/results/device_map.json; sleep 300

# Activate Python environment
# Run test with environment variables and log output
source $HOME/tt-metal-6u_test/python_env/bin/activate && \
    TT_METAL_HOME=$HOME/tt-metal-6u_test PYTHONPATH=$HOME/tt-metal-6u_test \
    time pytest $HOME/tt-metal-6u_test/tests/ttnn/stress_tests/ 2>&1 | tee $HOME/results/3_1_5_stress_test.log

# Check results
echo "Results:"
echo "--------------------------------------------------"
tail -n 15 $HOME/results/3_1_5_stress_test.log