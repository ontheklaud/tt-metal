#!/bin/bash

# Reset GLX
tt-smi -glx_reset; tt-smi -s > $HOME/results/device_map.json; sleep 300

# Remove csv result file if exist
mkdir -p $HOME/tt-metal-6u_test/generated
rm -f $HOME/tt-metal-6u_test/generated/matmul_2d_host_perf_report_BFLOAT4_BLoFi_traced.csv
rm -f $HOME/tt-metal-6u_test/generated/matmul_2d_host_perf_report_BFLOAT8_BHiFi2_traced.csv
rm -f $HOME/tt-metal-6u_test/generated/matmul_2d_host_perf_report_BFLOAT16HiFi4_traced.csv

# Activate Python environment
# Run test with environment variables and log output
source $HOME/tt-metal-6u_test/python_env/bin/activate && \
    TT_METAL_HOME=$HOME/tt-metal-6u_test PYTHONPATH=$HOME/tt-metal-6u_test \
    time $HOME/tt-metal-6u_test/build_Release_tracy/test/ttnn/unit_tests_ttnn \
    --gtest_filter="*Matmul2DHostPerfTest*" 2>&1 | \
    tee $HOME/results/3_2_1_matrix_multiplication_performance.log

# Check results
echo "Results:"
echo "--------------------------------------------------"
tail -n 20 $HOME/results/3_2_1_matrix_multiplication_performance.log

# Check performance
#BFLOAT4_B 8K^3 Stats
awk -F',' 'NR>1 && $2==8192 && $3==8192 && $4==8192 {
    t=$15; u=$NF; n++;
    ts+=t; us+=u; tsq+=t*t; usq+=u*u; tls+=log(t); uls+=log(u);
    tmin=(n==1||t<tmin)?t:tmin; tmax=(n==1||t>tmax)?t:tmax;
    umin=(n==1||u<umin)?u:umin; umax=(n==1||u>umax)?u:umax;
}
END {
    printf "%s:\n[n=%d min=%.2f(%.2f%%) max=%.2f(%.2f%%) avg=%.2f(%.2f%%) geomean=%.2f(%.2f%%) stdev=%.2f]\n",
           FILENAME, n, tmin, umin, tmax, umax, ts/n, us/n, exp(tls/n), exp(uls/n), sqrt(usq/n-(us/n)^2)
}' $HOME/tt-metal-6u_test/generated/matmul_2d_host_perf_report_BFLOAT4_BLoFi_traced.csv

#BFLOAT4_B 16K^3 Stats
awk -F',' 'NR>1 && $2==16384 && $3==16384 && $4==16384 {
    t=$15; u=$NF; n++;
    ts+=t; us+=u; tsq+=t*t; usq+=u*u; tls+=log(t); uls+=log(u);
    tmin=(n==1||t<tmin)?t:tmin; tmax=(n==1||t>tmax)?t:tmax;
    umin=(n==1||u<umin)?u:umin; umax=(n==1||u>umax)?u:umax;
}
END {
    printf "%s:\n[n=%d min=%.2f(%.2f%%) max=%.2f(%.2f%%) avg=%.2f(%.2f%%) geomean=%.2f(%.2f%%) stdev=%.2f]\n",
           FILENAME, n, tmin, umin, tmax, umax, ts/n, us/n, exp(tls/n), exp(uls/n), sqrt(usq/n-(us/n)^2)
}' $HOME/tt-metal-6u_test/generated/matmul_2d_host_perf_report_BFLOAT4_BLoFi_traced.csv

#BFLOAT8_B 8K^3 Stats
awk -F',' 'NR>1 && $2==8192 && $3==8192 && $4==8192 {
    t=$15; u=$NF; n++;
    ts+=t; us+=u; tsq+=t*t; usq+=u*u; tls+=log(t); uls+=log(u);
    tmin=(n==1||t<tmin)?t:tmin; tmax=(n==1||t>tmax)?t:tmax;
    umin=(n==1||u<umin)?u:umin; umax=(n==1||u>umax)?u:umax;
}
END {
    printf "%s:\n[n=%d min=%.2f(%.2f%%) max=%.2f(%.2f%%) avg=%.2f(%.2f%%) geomean=%.2f(%.2f%%) stdev=%.2f]\n",
           FILENAME, n, tmin, umin, tmax, umax, ts/n, us/n, exp(tls/n), exp(uls/n), sqrt(usq/n-(us/n)^2)
}' $HOME/tt-metal-6u_test/generated/matmul_2d_host_perf_report_BFLOAT8_BHiFi2_traced.csv

#BFLOAT8_B 16K^3 Stats
awk -F',' 'NR>1 && $2==16384 && $3==16384 && $4==16384 {
    t=$15; u=$NF; n++;
    ts+=t; us+=u; tsq+=t*t; usq+=u*u; tls+=log(t); uls+=log(u);
    tmin=(n==1||t<tmin)?t:tmin; tmax=(n==1||t>tmax)?t:tmax;
    umin=(n==1||u<umin)?u:umin; umax=(n==1||u>umax)?u:umax;
}
END {
    printf "%s:\n[n=%d min=%.2f(%.2f%%) max=%.2f(%.2f%%) avg=%.2f(%.2f%%) geomean=%.2f(%.2f%%) stdev=%.2f]\n",
           FILENAME, n, tmin, umin, tmax, umax, ts/n, us/n, exp(tls/n), exp(uls/n), sqrt(usq/n-(us/n)^2)
}' $HOME/tt-metal-6u_test/generated/matmul_2d_host_perf_report_BFLOAT8_BHiFi2_traced.csv

#BFLOAT16 8K^3 Stats
awk -F',' 'NR>1 && $2==8192 && $3==8192 && $4==8192 {
    t=$15; u=$NF; n++;
    ts+=t; us+=u; tsq+=t*t; usq+=u*u; tls+=log(t); uls+=log(u);
    tmin=(n==1||t<tmin)?t:tmin; tmax=(n==1||t>tmax)?t:tmax;
    umin=(n==1||u<umin)?u:umin; umax=(n==1||u>umax)?u:umax;
}
END {
    printf "%s:\n[n=%d min=%.2f(%.2f%%) max=%.2f(%.2f%%) avg=%.2f(%.2f%%) geomean=%.2f(%.2f%%) stdev=%.2f]\n",
           FILENAME, n, tmin, umin, tmax, umax, ts/n, us/n, exp(tls/n), exp(uls/n), sqrt(usq/n-(us/n)^2)
}' $HOME/tt-metal-6u_test/generated/matmul_2d_host_perf_report_BFLOAT16HiFi4_traced.csv

#BFLOAT16 16K^3 Stats
awk -F',' 'NR>1 && $2==16384 && $3==16384 && $4==16384 {
    t=$15; u=$NF; n++;
    ts+=t; us+=u; tsq+=t*t; usq+=u*u; tls+=log(t); uls+=log(u);
    tmin=(n==1||t<tmin)?t:tmin; tmax=(n==1||t>tmax)?t:tmax;
    umin=(n==1||u<umin)?u:umin; umax=(n==1||u>umax)?u:umax;
}
END {
    printf "%s:\n[n=%d min=%.2f(%.2f%%) max=%.2f(%.2f%%) avg=%.2f(%.2f%%) geomean=%.2f(%.2f%%) stdev=%.2f]\n",
           FILENAME, n, tmin, umin, tmax, umax, ts/n, us/n, exp(tls/n), exp(uls/n), sqrt(usq/n-(us/n)^2)
}' $HOME/tt-metal-6u_test/generated/matmul_2d_host_perf_report_BFLOAT16HiFi4_traced.csv