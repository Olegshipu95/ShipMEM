#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
results=${1:?Укажите новый каталог для результатов}
benchmark=CppTrader/temp/clang-23.1.5/cpptrader-performance-market_manager
input=CppTrader/tools/itch/sample.itch
mkdir -- "$results"

{
    date -Iseconds
    cat /proc/cmdline
    powerprofilesctl get
    cat /sys/devices/system/cpu/cpu1/cpufreq/{scaling_governor,energy_performance_preference,scaling_max_freq}
    perf --version
} > "$results/environment.txt"

cat "$input" > /dev/null
for run in warmup-1 warmup-2 warmup-3 {1..100}; do
    taskset -c 1 perf stat --no-big-num \
        -e cpu_core/cycles/u -e cpu_core/instructions/u \
        -e cpu_core/mem_load_retired.l3_miss/u \
        -e cpu_core/dtlb_load_misses.walk_completed/u \
        -e task-clock -e context-switches -e cpu-migrations \
        -- "$benchmark" < "$input" \
        > "$results/bench-$run.txt" 2> "$results/perf-$run.txt"
done
