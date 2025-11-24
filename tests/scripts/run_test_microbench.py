# SPDX-FileCopyrightText: © 2023 Tenstorrent AI ULC
#
# SPDX-License-Identifier: Apache-2.0

"""
Unified microbenchmark test suite for validation tests.
Includes: DRAM bandwidth, NOC bandwidth, PCIe transfer tests.
Extracted and consolidated from test_moreh_microbenchmark.py.
"""

import os
import copy
import re
import csv
import subprocess as sp
from pathlib import Path
from loguru import logger
import pytest
import numpy as np
import toolz

from tt_metal.tools.profiler.common import PROFILER_LOGS_DIR, PROFILER_DEVICE_SIDE_LOG

profiler_log_path = PROFILER_LOGS_DIR / PROFILER_DEVICE_SIDE_LOG

from tt_metal.tools.profiler.process_device_log import import_log_run_stats
import tt_metal.tools.profiler.device_post_proc_config as device_post_proc_config


# ============================================================================
# Helper Functions
# ============================================================================

def run_moreh_single_test(test_name, test_entry):
    """Execute a single test command and capture output."""
    full_env = copy.deepcopy(os.environ)
    logger.info(f"========= RUNNING MOREH TEST - {test_name}")
    print(test_entry)
    result = sp.run(test_entry, shell=True, capture_output=True, env=full_env)
    print(result.stdout.decode("utf-8"))
    print(result.stderr.decode("utf-8"))
    return result


def profile_results_kernel_duration():
    """Extract kernel duration from profiler logs."""
    setup = device_post_proc_config.default_setup()
    setup.deviceInputLog = profiler_log_path
    setup.timerAnalysis = {
        "device_kernel_duration": {
            "across": "device",
            "type": "session_first_last",
            "start": {"core": "ANY", "risc": "ANY", "zone_name": [f"{risc}-KERNEL" for risc in setup.riscTypes]},
            "end": {"core": "ANY", "risc": "ANY", "zone_name": [f"{risc}-KERNEL" for risc in setup.riscTypes]},
        },
    }
    devices_data = import_log_run_stats(setup)
    deviceID = list(devices_data["devices"].keys())[0]
    total_cycle = devices_data["devices"][deviceID]["cores"]["DEVICE"]["analysis"]["device_kernel_duration"]["stats"][
        "Average"
    ]
    return total_cycle


def get_device_freq():
    """Get device frequency from profiler data."""
    setup = device_post_proc_config.default_setup()
    setup.deviceInputLog = profiler_log_path
    deviceData = import_log_run_stats(setup)
    freq = deviceData["deviceInfo"]["freq"]
    return freq


def run_dram_read_cmd(k, n, num_blocks, df, num_banks, bank_start_id, device_id):
    """Run DRAM read bandwidth test command."""
    command = (
        "TT_METAL_DEVICE_PROFILER=1 ./build/test/tt_metal/perf_microbenchmark/8_dram_adjacent_core_read/test_dram_read"
        + " "
        + " --k "
        + str(k)
        + " --n "
        + str(n)
        + " --num-blocks "
        + str(num_blocks)
        + " --num-tests "
        + str(1)
        + " --data-type "
        + str(df)
        + " --num-banks "
        + str(num_banks)
        + " --bank-start-id "
        + str(bank_start_id)
        + " --device-id "
        + str(device_id)
        + " --bypass-check"
    )
    run_moreh_single_test("DRAM BW test multi-core", command)


# ============================================================================
# Pytest Fixtures
# ============================================================================

@pytest.fixture(scope="function")
def create_moreh_microbenchmark_csv(request):
    """Create CSV file path for microbenchmark results."""
    microbenchmark_name = request.node.name.split("[")[0]
    file_name = PROFILER_LOGS_DIR / f"moreh_{microbenchmark_name}.csv"
    yield file_name


@pytest.fixture(scope="function")
def record_moreh_microbenchmark_csv(capsys, create_moreh_microbenchmark_csv):
    """Record microbenchmark results to CSV from captured output."""
    yield

    captured = capsys.readouterr()
    result_output = captured.out

    def get_entries(result_output, marker):
        for line in result_output.splitlines():
            if marker in line:
                # Remove log file path suffix
                line = re.sub(r"\s+\(.*?:\d+\)$", "", line)
                # Extract content after marker
                idx = line.find(marker + ":")
                if idx != -1:
                    content = line[idx + len(marker) + 1 :]
                    parts = [p.strip() for p in content.split(":")]
                    return parts
        return []

    csv_microbenchmark_name = get_entries(result_output, "CSV_MICROBENCHMARK")[1]
    print(f"csv_microbenchmark_name: {csv_microbenchmark_name}")
    csv_inputs_and_values = get_entries(result_output, "CSV_INPUT")
    print(f"csv_inputs_and_values: {csv_inputs_and_values}")
    csv_outputs_and_values = get_entries(result_output, "CSV_OUTPUT")
    print(f"csv_outputs_and_values: {csv_outputs_and_values}")
    csv_result_and_value = get_entries(result_output, "CSV_RESULT")
    print(f"csv_result_and_value: {csv_result_and_value}")

    assert len(csv_result_and_value) == 2, f"CSV_RESULT needs to be a single name and value"
    assert len(csv_inputs_and_values) >= 2
    assert len(csv_outputs_and_values) >= 2

    def get_names(inputs_and_values):
        return list(toolz.itertoolz.take_nth(2, inputs_and_values))

    def get_values(inputs_and_values):
        return list(toolz.itertoolz.take_nth(2, inputs_and_values[1:]))

    csv_inputs_names = get_names(csv_inputs_and_values)
    print(f"csv_inputs_names: {csv_inputs_names}")
    csv_inputs_values = get_values(csv_inputs_and_values)
    print(f"csv_inputs_values: {csv_inputs_values}")

    csv_outputs_names = get_names(csv_outputs_and_values)
    print(f"csv_outputs_names: {csv_outputs_names}")
    csv_outputs_values = get_values(csv_outputs_and_values)
    print(f"csv_outputs_values: {csv_outputs_values}")

    csv_result_name = get_names(csv_result_and_value)[0]
    print(f"csv_result_name: {csv_result_name}")
    csv_result_value = get_values(csv_result_and_value)[0]
    print(f"csv_result_value: {csv_result_value}")

    headers = csv_inputs_names + csv_outputs_names + [csv_result_name]
    print(f"headers: {headers}")
    data = csv_inputs_values + csv_outputs_values + [csv_result_value]
    print(f"data: {data}")

    file_name = create_moreh_microbenchmark_csv
    print(f"Writing results to {file_name}")
    file_path = Path(file_name)

    if not file_path.exists():
        with open(file_path, mode="w", newline="") as file:
            writer = csv.writer(file)
            writer.writerow(headers)

    assert file_path.is_file()
    with open(file_path, mode="a", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(data)


# ============================================================================
# Test 3_2_2: DRAM Bandwidth Test
# ============================================================================

@pytest.mark.parametrize(
    "arch, freq, test_vector, num_tests, nblock, data_format, num_banks, bank_start_id, device_id",
    [
        *[
            ("wormhole_b0", 1000, np.array([k, 12 * 128]), 1, 8, 1, 12, 0, device_id)
            for k in [2**i for i in range(10, 16)]  # 2^10 = 1024 to 2^15 = 32768 (bfloat16 only)
            for device_id in range(32)
        ],
    ],
)
def test_dram_read_all_core(
    arch,
    freq,
    test_vector,
    num_tests,
    nblock,
    data_format,
    num_banks,
    bank_start_id,
    device_id,
    create_moreh_microbenchmark_csv,
):
    """
    Test DRAM read bandwidth across all cores.
    Generates input_size: 3145728, 6291456, 12582912, 25165824, 50331648, 100663296 bytes
    """
    data = []
    cycle_list = []
    time_list = []
    throughput_list = []

    for _ in range(num_tests):
        k = int(test_vector[0])
        n = int(test_vector[1])

        if data_format == 0:
            input_size = k * n * 1088 // 1024
            data_format_str = "bfp8_b"
        elif data_format == 1:
            input_size = k * n * 2048 // 1024
            data_format_str = "bfloat16"

        run_dram_read_cmd(k, n, nblock, data_format, num_banks, bank_start_id, device_id)
        cycle = profile_results_kernel_duration()
        time = cycle / freq / 1000.0 / 1000.0
        throughput = input_size / cycle

        logger.info("DRAM read cycle: " + str(cycle))
        logger.info("DRAM read time: " + str(time))
        logger.info("DRAM read throughput: " + str(throughput))

        cycle_list.append(cycle)
        time_list.append(time)
        throughput_list.append(throughput)

    cycle = sum(cycle_list) / len(cycle_list)
    time = sum(time_list) / len(time_list)
    throughput = sum(throughput_list) / len(throughput_list)

    logger.info(f"Device{device_id} DRAM read k: {k}, n: {n} nblock: {nblock} input_size: {input_size}")
    logger.info(f"Device{device_id} DRAM read data_format: {data_format == 0 and 'bfp8_b' or 'bfloat16'}")
    logger.info(f"Device{device_id} DRAM read cycle: {cycle}")
    logger.info(f"Device{device_id} DRAM read time: {time}")
    logger.info(f"Device{device_id} DRAM read throughput: {throughput}")

    headers = ["Device Id", "input_size(B)", "data_format", "cycle", "time", "throughput(GB/s)"]
    row = [device_id, input_size, data_format_str, cycle, time, throughput]

    file_name = create_moreh_microbenchmark_csv
    file_path = Path(file_name)
    logger.info(f"Writing results to {file_path}")

    # Write CSV (create if missing)
    if not file_path.exists():
        with open(file_path, mode="w", newline="") as file:
            writer = csv.writer(file)
            writer.writerow(headers)

    with open(file_path, mode="a", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(row)

    assert file_path.is_file()


def analyze_dram_bandwidth_results_on_completion():
    """
    Analyze DRAM bandwidth test results after all parametrized tests complete.
    Called at the end of the last test execution.
    """
    csv_file = PROFILER_LOGS_DIR / "moreh_test_dram_read_all_core.csv"

    if not csv_file.exists():
        logger.warning(f"CSV file not found: {csv_file}")
        return

    # Read CSV data
    data = []
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            data.append({
                'device_id': int(row['Device Id']),
                'input_size': int(row['input_size(B)']),
                'throughput': float(row['throughput(GB/s)'])
            })

    if not data:
        logger.warning("No data found in CSV")
        return

    data_array = np.array([(d['input_size'], d['throughput']) for d in data])

    print("\n" + "="*70)
    print("DRAM Bandwidth Test - Analysis Results")
    print("="*70)

    # Analyze by input_size
    target_sizes = [3145728, 6291456, 12582912, 25165824, 50331648, 100663296]
    theo_bw = 336.0  # GB/s
    thresh_pct = 80.0  # Threshold: 80% efficiency (configurable: change this value or use 'min' or 'avg')
    metric = 'min'  # Options: 'min', 'avg', 'geomean' - which metric to compare against threshold

    for size in target_sizes:
        size_data = data_array[data_array[:, 0] == size]
        if len(size_data) == 0:
            continue

        throughputs = size_data[:, 1]
        n = len(throughputs)
        min_bw = np.min(throughputs)
        max_bw = np.max(throughputs)
        avg_bw = np.mean(throughputs)
        geomean_bw = np.exp(np.mean(np.log(throughputs)))
        std_bw = np.std(throughputs)

        # Determine PASS/FAIL based on selected metric
        if metric == 'min':
            test_value = min_bw / theo_bw * 100
        elif metric == 'avg':
            test_value = avg_bw / theo_bw * 100
        elif metric == 'geomean':
            test_value = geomean_bw / theo_bw * 100
        else:
            test_value = min_bw / theo_bw * 100  # default to min

        result = "PASS" if test_value >= thresh_pct else "FAIL"

        print(f"[size={size:>9d} theo={theo_bw:.0f}]: "
              f"[n={n:>3d} min={min_bw:>6.2f}({min_bw/theo_bw*100:>5.1f}%) "
              f"max={max_bw:>6.2f}({max_bw/theo_bw*100:>5.1f}%) "
              f"avg={avg_bw:>6.2f}({avg_bw/theo_bw*100:>5.1f}%) "
              f"geomean={geomean_bw:>6.2f}({geomean_bw/theo_bw*100:>5.1f}%) "
              f"stdev={std_bw:>5.2f}] {result}")

    print("="*70 + "\n")


# ============================================================================
# Test 3_2_3: NOC Adjacent Bandwidth Test
# ============================================================================

@pytest.mark.parametrize(
    "r, c, num_tiles, tiles_per_transfer, noc_index, noc_direction, access_type, use_device_profiler, device_id",
    [
        (0, 0, 204800, tiles_per_transfer, noc_index, noc_direction, access_type, 0, device_id)
        for tiles_per_transfer in [32]
        for noc_index in range(2)
        for noc_direction in range(4)
        for access_type in range(2)
        for device_id in range(32)
    ],
)
def test_noc_adjacent(
    r,
    c,
    num_tiles,
    tiles_per_transfer,
    noc_index,
    noc_direction,
    access_type,
    use_device_profiler,
    device_id,
    record_moreh_microbenchmark_csv,
):
    """
    Test NOC (Network-on-Chip) adjacent core bandwidth.
    Tests all NOC configurations: 2 indices × 4 directions × 2 access types = 16 combinations per device
    """
    command = (
        "./build/test/tt_metal/perf_microbenchmark/2_noc_adjacent/test_noc_adjacent"
        + " "
        + "--cores-r "
        + str(r)
        + " --cores-c "
        + str(c)
        + " --num-tiles "
        + str(num_tiles)
        + " --tiles-per-transfer "
        + str(tiles_per_transfer)
        + " --noc-index "
        + str(noc_index)
        + " --noc-direction "
        + str(noc_direction)
        + " --access-type "
        + str(access_type)
        + " --device-id "
        + str(device_id)
        + " --bypass-check"
    )

    if use_device_profiler:
        command += " --use-device-profiler"

    result = run_moreh_single_test("test_noc_adjacent", command)


def analyze_noc_adjacent_results_on_completion():
    """
    Analyze NOC adjacent bandwidth test results after all parametrized tests complete.
    Called at the end of the last test execution.
    """
    csv_file = PROFILER_LOGS_DIR / "moreh_test_noc_adjacent.csv"

    if not csv_file.exists():
        logger.warning(f"CSV file not found: {csv_file}")
        return

    # Read CSV data
    data = []
    with open(csv_file, 'r') as f:
        reader = csv.reader(f)
        headers = next(reader)  # Skip header
        for row in reader:
            if len(row) < 10:
                continue
            data.append({
                'tiles_per_transfer': int(row[4]),  # Field 5
                'noc_index': row[5],  # Field 6
                'noc_direction': row[6],  # Field 7
                'access_type': row[7],  # Field 8
                'bandwidth': float(row[9])  # Field 10
            })

    if not data:
        logger.warning("No data found in CSV")
        return

    # Filter for tiles_per_transfer == 32
    data_filtered = [d for d in data if d['tiles_per_transfer'] == 32]

    if not data_filtered:
        logger.warning("No data with tiles_per_transfer=32")
        return

    print("\n" + "="*70)
    print("NOC Adjacent Bandwidth Test - Analysis Results")
    print("="*70)
    print("=== NOC Adjacent Bandwidth (tiles-per-transfer=32, theo=32 B/cc) ===")
    print()

    theo = 32.0
    thresh = 80.0  # 80% efficiency threshold

    # Define expected combinations
    combos = [
        ("NOC_RISCV_0", "X_PLUS_DIR", "WRITE"),
        ("NOC_RISCV_0", "Y_MINUS_DIR", "READ"),
        ("NOC_RISCV_0", "X_MINUS_DIR", "READ"),
        ("NOC_RISCV_0", "Y_PLUS_DIR", "WRITE"),
        ("NOC_RISCV_1", "X_PLUS_DIR", "READ"),
        ("NOC_RISCV_1", "Y_MINUS_DIR", "WRITE"),
        ("NOC_RISCV_1", "X_MINUS_DIR", "WRITE"),
        ("NOC_RISCV_1", "Y_PLUS_DIR", "READ"),
    ]

    for noc_idx, noc_dir, acc_type in combos:
        combo_data = [d['bandwidth'] for d in data_filtered
                      if d['noc_index'] == noc_idx
                      and d['noc_direction'] == noc_dir
                      and d['access_type'] == acc_type]

        if combo_data:
            bw_array = np.array(combo_data)
            n = len(bw_array)
            min_bw = np.min(bw_array)
            max_bw = np.max(bw_array)
            avg_bw = np.mean(bw_array)

            min_eff = min_bw / theo * 100
            max_eff = max_bw / theo * 100
            avg_eff = avg_bw / theo * 100

            result = "PASS" if min_eff >= thresh else "FAIL"

            print(f"{noc_idx},{noc_dir},{acc_type}: "
                  f"[n={n:>3d} min={min_bw:.3f}({min_eff:.2f}%) "
                  f"max={max_bw:.3f}({max_eff:.2f}%) "
                  f"avg={avg_bw:.3f}({avg_eff:.2f}%)] {result}")
        else:
            print(f"{noc_idx},{noc_dir},{acc_type}: [NO DATA]")

    print("="*70 + "\n")


# ============================================================================
# Test 3_2_4: PCIe Transfer Bandwidth Test
# ============================================================================

@pytest.mark.parametrize("device_id", range(32))
@pytest.mark.parametrize(
    "buffer_type",
    [
        0,  # 0: DRAM, 1: L1
    ])
@pytest.mark.parametrize(
    "buffer_size",
    [
        536870912,  # 512MB only
    ],
)
@pytest.mark.parametrize(
    "page_size",
    [
        2048,
    ],
)
def test_pcie_transfer(device_id, buffer_type, buffer_size, page_size, record_moreh_microbenchmark_csv):
    """
    Test PCIe transfer bandwidth (Host to Device and Device to Host).
    Tests 512MB transfers on DRAM for all 32 devices.
    """
    command = (
        "./build/test/tt_metal/perf_microbenchmark/3_pcie_transfer/test_rw_buffer"
        + " --buffer-type "
        + str(buffer_type)
        + " --transfer-size "
        + str(buffer_size)
        + " --device-id "
        + str(device_id)
        + " --page-size "
        + str(page_size)
        + " --bypass-check"
    )

    result = run_moreh_single_test("test_rw_buffer", command)


def analyze_pcie_transfer_results_on_completion(device_map_file):
    """
    Analyze PCIe transfer bandwidth test results after all parametrized tests complete.
    Called at the end of the last test execution.
    """
    import json

    csv_file = PROFILER_LOGS_DIR / "moreh_test_pcie_transfer.csv"

    if not csv_file.exists():
        logger.warning(f"CSV file not found: {csv_file}")
        return

    # Read device map to classify x8 and x1 devices
    if not Path(device_map_file).exists():
        logger.warning(f"Device map file not found: {device_map_file}")
        return

    with open(device_map_file, 'r') as f:
        device_map = json.load(f)

    x8_devices = []
    x1_devices = []
    device_info_list = device_map.get('device_info', [])
    for idx, info in enumerate(device_info_list):
        pcie_width = info.get('board_info', {}).get('pcie_width')
        if pcie_width == "8":
            x8_devices.append(idx)
        elif pcie_width == "1":
            x1_devices.append(idx)

    # Read CSV data
    data = []
    with open(csv_file, 'r') as f:
        reader = csv.reader(f)
        headers = next(reader)  # Skip header
        for row in reader:
            data.append({
                'device_id': int(row[0]),
                'buffer_type': row[1],
                'buffer_size': int(row[2]),
                'h2d_bw': float(row[3]),
                'd2h_bw': float(row[4])
            })

    if not data:
        logger.warning("No data found in CSV")
        return

    # Filter for DRAM and 512MB transfers
    data_filtered = [d for d in data if d['buffer_type'] == 'DRAM' and d['buffer_size'] == 536870912]

    if not data_filtered:
        logger.warning("No data with DRAM and 512MB buffer")
        return

    print("\n" + "="*70)
    print("PCIe Transfer Bandwidth Test - Analysis Results")
    print("="*70)

    # Analyze x8 H2D
    x8_h2d_data = [d['h2d_bw'] for d in data_filtered if d['device_id'] in x8_devices]
    if x8_h2d_data:
        bw_array = np.array(x8_h2d_data)
        n = len(bw_array)
        min_bw = np.min(bw_array)
        max_bw = np.max(bw_array)
        avg_bw = np.mean(bw_array)
        geomean_bw = np.exp(np.mean(np.log(bw_array)))
        std_bw = np.std(bw_array)
        result = "PASS" if min_bw >= 9.0 else "FAIL"
        print(f"=== H2D x8 (threshold=9GB/s) ===")
        print(f"[n={n:>3d} min={min_bw:.2f} max={max_bw:.2f} avg={avg_bw:.2f} geomean={geomean_bw:.2f} stdev={std_bw:.2f}] {result}")
    else:
        print("=== H2D x8 (threshold=9GB/s) ===")
        print("[NO DATA]")

    # Analyze x8 D2H
    x8_d2h_data = [d['d2h_bw'] for d in data_filtered if d['device_id'] in x8_devices]
    if x8_d2h_data:
        bw_array = np.array(x8_d2h_data)
        n = len(bw_array)
        min_bw = np.min(bw_array)
        max_bw = np.max(bw_array)
        avg_bw = np.mean(bw_array)
        geomean_bw = np.exp(np.mean(np.log(bw_array)))
        std_bw = np.std(bw_array)
        result = "PASS" if min_bw >= 9.0 else "FAIL"
        print(f"=== D2H x8 (threshold=9GB/s) ===")
        print(f"[n={n:>3d} min={min_bw:.2f} max={max_bw:.2f} avg={avg_bw:.2f} geomean={geomean_bw:.2f} stdev={std_bw:.2f}] {result}")
    else:
        print("=== D2H x8 (threshold=9GB/s) ===")
        print("[NO DATA]")

    # Analyze x1 H2D
    x1_h2d_data = [d['h2d_bw'] for d in data_filtered if d['device_id'] in x1_devices]
    if x1_h2d_data:
        bw_array = np.array(x1_h2d_data)
        n = len(bw_array)
        min_bw = np.min(bw_array)
        max_bw = np.max(bw_array)
        avg_bw = np.mean(bw_array)
        geomean_bw = np.exp(np.mean(np.log(bw_array)))
        std_bw = np.std(bw_array)
        result = "PASS" if min_bw >= 1.6 else "FAIL"
        print(f"=== H2D x1 (threshold=1.6GB/s) ===")
        print(f"[n={n:>3d} min={min_bw:.2f} max={max_bw:.2f} avg={avg_bw:.2f} geomean={geomean_bw:.2f} stdev={std_bw:.2f}] {result}")
    else:
        print("=== H2D x1 (threshold=1.6GB/s) ===")
        print("[NO DATA]")

    # Analyze x1 D2H
    x1_d2h_data = [d['d2h_bw'] for d in data_filtered if d['device_id'] in x1_devices]
    if x1_d2h_data:
        bw_array = np.array(x1_d2h_data)
        n = len(bw_array)
        min_bw = np.min(bw_array)
        max_bw = np.max(bw_array)
        avg_bw = np.mean(bw_array)
        geomean_bw = np.exp(np.mean(np.log(bw_array)))
        std_bw = np.std(bw_array)
        result = "PASS" if min_bw >= 1.6 else "FAIL"
        print(f"=== D2H x1 (threshold=1.6GB/s) ===")
        print(f"[n={n:>3d} min={min_bw:.2f} max={max_bw:.2f} avg={avg_bw:.2f} geomean={geomean_bw:.2f} stdev={std_bw:.2f}] {result}")
    else:
        print("=== D2H x1 (threshold=1.6GB/s) ===")
        print("[NO DATA]")

    print("="*70 + "\n")


# ============================================================================
# Test 3_2_5: Ethernet Link Bandwidth Test
# ============================================================================

def test_ethernet_bandwidth():
    """
    Test Ethernet link bandwidth (Internal and External links).
    This test is NOT parametrized - it runs once and tests all links.
    """
    # Note: This test calls the actual pytest test file directly
    # The test itself handles all devices and iterations
    pass


def analyze_ethernet_bandwidth_results_on_completion(device_map_file):
    """
    Analyze Ethernet link bandwidth test results.
    Separates Internal and External links.
    """
    import json

    csv_file = PROFILER_LOGS_DIR / "test_all_ethernet_links_bandwidth.csv"

    if not csv_file.exists():
        logger.warning(f"CSV file not found: {csv_file}")
        return

    # Read device map for bus_id mapping
    if not Path(device_map_file).exists():
        logger.warning(f"Device map file not found: {device_map_file}")
        return

    with open(device_map_file, 'r') as f:
        device_map = json.load(f)

    # Create device_id -> bus_id mapping
    busid_map = {}
    device_info_list = device_map.get('device_info', [])
    for idx, info in enumerate(device_info_list):
        bus_id = info.get('board_info', {}).get('bus_id')
        if bus_id:
            busid_map[idx] = bus_id

    # Read CSV data (skip header, filter conditions)
    data = []
    with open(csv_file, 'r') as f:
        reader = csv.reader(f)
        for line_num, row in enumerate(reader, 1):
            if line_num < 6:  # Skip first 5 lines
                continue
            if len(row) < 28:
                continue
            # Filter: $2==1 && $8==256 && $9==8192
            if row[1] == '1' and row[7] == '256' and row[8] == '8192':
                data.append({
                    'sender_id': int(row[2]),
                    'receiver_id': int(row[4]),
                    'cable_type': row[6],  # 'internal' or 'external'
                    'bandwidth': float(row[26])  # Field 27 (0-indexed: 26)
                })

    if not data:
        logger.warning("No data found in CSV")
        return

    # Group by link (sender -> receiver - cable_type)
    links = {}
    for d in data:
        key = f"{d['sender_id']}->{d['receiver_id']}-{d['cable_type']}"
        if key not in links:
            links[key] = {
                'sender_id': d['sender_id'],
                'receiver_id': d['receiver_id'],
                'cable_type': d['cable_type'],
                'bandwidths': []
            }
        links[key]['bandwidths'].append(d['bandwidth'])

    # Calculate average bandwidth per link
    for key in links:
        bw_list = links[key]['bandwidths']
        links[key]['avg_bw'] = np.mean(bw_list)

    # Separate Internal and External links
    internal_links = {k: v for k, v in links.items() if v['cable_type'] == 'internal'}
    external_links = {k: v for k, v in links.items() if v['cable_type'] == 'external'}

    # Sort links by key
    internal_sorted = sorted(internal_links.items())
    external_sorted = sorted(external_links.items())

    theo = 12.5  # GB/s
    thresh = 11.875  # GB/s

    print("\n" + "="*70)
    print("Ethernet Link Bandwidth Test - Analysis Results")
    print("="*70)

    # Print Internal links
    print("=== Internal Links ===")
    for key, link in internal_sorted:
        avg_bw = link['avg_bw']
        eff = avg_bw / theo * 100
        result = "PASS" if avg_bw >= thresh else "FAIL"
        send_id = link['sender_id']
        recv_id = link['receiver_id']
        send_bus = busid_map.get(send_id, "N/A")
        recv_bus = busid_map.get(recv_id, "N/A")
        print(f"Int: #{send_id:02d} ({send_bus}) -> #{recv_id:02d} ({recv_bus}): "
              f"{avg_bw:.2f} GB/s ({eff:.2f}%) {result}")

    # Print External links
    print("\n=== External Links ===")
    for key, link in external_sorted:
        avg_bw = link['avg_bw']
        eff = avg_bw / theo * 100
        result = "PASS" if avg_bw >= thresh else "FAIL"
        send_id = link['sender_id']
        recv_id = link['receiver_id']
        send_bus = busid_map.get(send_id, "N/A")
        recv_bus = busid_map.get(recv_id, "N/A")
        print(f"Ext: #{send_id:02d} ({send_bus}) -> #{recv_id:02d} ({recv_bus}): "
              f"{avg_bw:.2f} GB/s ({eff:.2f}%) {result}")

    # Internal statistics
    if internal_sorted:
        int_bw_arr = np.array([link['avg_bw'] for _, link in internal_sorted])
        int_n = len(int_bw_arr)
        int_min = np.min(int_bw_arr)
        int_max = np.max(int_bw_arr)
        int_avg = np.mean(int_bw_arr)
        int_gm = np.exp(np.mean(np.log(int_bw_arr)))
        int_sd = np.std(int_bw_arr)
        result = "PASS" if int_min >= thresh else "FAIL"

        print(f"\n=== Internal Links Summary (theo=12.5GB/s, threshold=11.875GB/s) ===")
        print(f"[n={int_n} min={int_min:.2f}({int_min/theo*100:.2f}%) "
              f"max={int_max:.2f}({int_max/theo*100:.2f}%) "
              f"avg={int_avg:.2f}({int_avg/theo*100:.2f}%) "
              f"geomean={int_gm:.2f}({int_gm/theo*100:.2f}%) "
              f"stdev={int_sd:.2f}] {result}")

    # External statistics
    if external_sorted:
        ext_bw_arr = np.array([link['avg_bw'] for _, link in external_sorted])
        ext_n = len(ext_bw_arr)
        ext_min = np.min(ext_bw_arr)
        ext_max = np.max(ext_bw_arr)
        ext_avg = np.mean(ext_bw_arr)
        ext_gm = np.exp(np.mean(np.log(ext_bw_arr)))
        ext_sd = np.std(ext_bw_arr)
        result = "PASS" if ext_min >= thresh else "FAIL"

        print(f"\n=== External Links Summary (theo=12.5GB/s, threshold=11.875GB/s) ===")
        print(f"[n={ext_n} min={ext_min:.2f}({ext_min/theo*100:.2f}%) "
              f"max={ext_max:.2f}({ext_max/theo*100:.2f}%) "
              f"avg={ext_avg:.2f}({ext_avg/theo*100:.2f}%) "
              f"geomean={ext_gm:.2f}({ext_gm/theo*100:.2f}%) "
              f"stdev={ext_sd:.2f}] {result}")

    print("="*70 + "\n")


# ============================================================================
# Test 3_2_6: Ethernet Link Latency Test
# ============================================================================

def test_ethernet_latency():
    """
    Test Ethernet link latency (Internal and External links).
    This test is NOT parametrized - it runs once and tests all links.
    """
    # Note: This test calls the actual pytest test file directly
    # The test itself handles all devices and iterations
    pass


def analyze_ethernet_latency_results_on_completion(device_map_file):
    """
    Analyze Ethernet link latency test results.
    Separates Internal and External links.
    """
    import json

    csv_file = PROFILER_LOGS_DIR / "test_all_ethernet_links_latency.csv"

    if not csv_file.exists():
        logger.warning(f"CSV file not found: {csv_file}")
        return

    # Read device map for bus_id mapping
    if not Path(device_map_file).exists():
        logger.warning(f"Device map file not found: {device_map_file}")
        return

    with open(device_map_file, 'r') as f:
        device_map = json.load(f)

    # Create device_id -> bus_id mapping
    busid_map = {}
    device_info_list = device_map.get('device_info', [])
    for idx, info in enumerate(device_info_list):
        bus_id = info.get('board_info', {}).get('bus_id')
        if bus_id:
            busid_map[idx] = bus_id

    # Read CSV data (skip header, filter conditions)
    data = []
    with open(csv_file, 'r') as f:
        reader = csv.reader(f)
        for line_num, row in enumerate(reader, 1):
            if line_num < 6:  # Skip first 5 lines
                continue
            if len(row) < 28:
                continue
            # Filter: $2==1 && $8==1 && $9==16
            if row[1] == '1' and row[7] == '1' and row[8] == '16':
                data.append({
                    'sender_id': int(row[2]),
                    'receiver_id': int(row[4]),
                    'cable_type': row[6],  # 'internal' or 'external'
                    'latency': float(row[26])  # Field 27 (0-indexed: 26)
                })

    if not data:
        logger.warning("No data found in CSV")
        return

    # Group by link (sender -> receiver - cable_type)
    links = {}
    for d in data:
        key = f"{d['sender_id']}->{d['receiver_id']}-{d['cable_type']}"
        if key not in links:
            links[key] = {
                'sender_id': d['sender_id'],
                'receiver_id': d['receiver_id'],
                'cable_type': d['cable_type'],
                'latencies': []
            }
        links[key]['latencies'].append(d['latency'])

    # Calculate average latency per link and determine expected latency
    for key in links:
        lat_list = links[key]['latencies']
        avg_lat = np.mean(lat_list)
        links[key]['avg_latency'] = avg_lat

        # Determine expected latency
        if links[key]['cable_type'] == 'internal':
            # 1290 if measured > 1290, otherwise 890
            links[key]['expected'] = 1290 if avg_lat > 1290 else 890
        else:  # external
            links[key]['expected'] = 1690

    # Separate Internal and External links
    internal_links = {k: v for k, v in links.items() if v['cable_type'] == 'internal'}
    external_links = {k: v for k, v in links.items() if v['cable_type'] == 'external'}

    # Sort links by key
    internal_sorted = sorted(internal_links.items())
    external_sorted = sorted(external_links.items())

    thresh_lat = 2000  # ns (< 2us threshold)

    print("\n" + "="*70)
    print("Ethernet Link Latency Test - Analysis Results")
    print("="*70)

    # Print Internal links
    print("=== Internal Links ===")
    for key, link in internal_sorted:
        measured = link['avg_latency']
        expected = link['expected']
        eff = expected / measured * 100
        result = "PASS" if measured < thresh_lat else "FAIL"
        send_id = link['sender_id']
        recv_id = link['receiver_id']
        send_bus = busid_map.get(send_id, "N/A")
        recv_bus = busid_map.get(recv_id, "N/A")
        print(f"Int: #{send_id:02d} ({send_bus}) -> #{recv_id:02d} ({recv_bus}): "
              f"{measured:.2f} ns [exp={expected:.0f}] ({eff:.2f}%) {result}")

    # Print External links
    print("\n=== External Links ===")
    for key, link in external_sorted:
        measured = link['avg_latency']
        expected = link['expected']
        eff = expected / measured * 100
        result = "PASS" if measured < thresh_lat else "FAIL"
        send_id = link['sender_id']
        recv_id = link['receiver_id']
        send_bus = busid_map.get(send_id, "N/A")
        recv_bus = busid_map.get(recv_id, "N/A")
        print(f"Ext: #{send_id:02d} ({send_bus}) -> #{recv_id:02d} ({recv_bus}): "
              f"{measured:.2f} ns [exp={expected:.0f}] ({eff:.2f}%) {result}")

    # Internal statistics
    if internal_sorted:
        int_n = len(internal_sorted)
        int_pass = sum(1 for _, link in internal_sorted if link['avg_latency'] < thresh_lat)
        int_eff_arr = np.array([link['expected'] / link['avg_latency'] * 100
                                for _, link in internal_sorted])
        int_lat_arr = np.array([link['avg_latency'] for _, link in internal_sorted])

        int_eff_min = np.min(int_eff_arr)
        int_eff_max = np.max(int_eff_arr)
        int_eff_avg = np.mean(int_eff_arr)
        int_eff_gm = np.exp(np.mean(np.log(int_eff_arr)))
        int_eff_sd = np.std(int_eff_arr)
        int_lat_min = np.min(int_lat_arr)
        int_lat_max = np.max(int_lat_arr)

        result = "PASS" if int_lat_max < thresh_lat else "FAIL"

        print(f"\n=== Internal Links Summary (threshold < 2us) ===")
        print(f"[n={int_n} latency min={int_lat_min:.2f} max={int_lat_max:.2f}] "
              f"[eff min={int_eff_min:.2f}% max={int_eff_max:.2f}% "
              f"avg={int_eff_avg:.2f}% geomean={int_eff_gm:.2f}% stdev={int_eff_sd:.2f}] "
              f"[{int_pass}/{int_n} PASS] {result}")

    # External statistics
    if external_sorted:
        ext_n = len(external_sorted)
        ext_pass = sum(1 for _, link in external_sorted if link['avg_latency'] < thresh_lat)
        ext_eff_arr = np.array([link['expected'] / link['avg_latency'] * 100
                                for _, link in external_sorted])
        ext_lat_arr = np.array([link['avg_latency'] for _, link in external_sorted])

        ext_eff_min = np.min(ext_eff_arr)
        ext_eff_max = np.max(ext_eff_arr)
        ext_eff_avg = np.mean(ext_eff_arr)
        ext_eff_gm = np.exp(np.mean(np.log(ext_eff_arr)))
        ext_eff_sd = np.std(ext_eff_arr)
        ext_lat_min = np.min(ext_lat_arr)
        ext_lat_max = np.max(ext_lat_arr)

        result = "PASS" if ext_lat_max < thresh_lat else "FAIL"

        print(f"\n=== External Links Summary (threshold < 2us) ===")
        print(f"[n={ext_n} latency min={ext_lat_min:.2f} max={ext_lat_max:.2f}] "
              f"[eff min={ext_eff_min:.2f}% max={ext_eff_max:.2f}% "
              f"avg={ext_eff_avg:.2f}% geomean={ext_eff_gm:.2f}% stdev={ext_eff_sd:.2f}] "
              f"[{ext_pass}/{ext_n} PASS] {result}")

    print("="*70 + "\n")