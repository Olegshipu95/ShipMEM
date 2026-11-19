#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../CppTrader"
case ${1:-main} in
    main) build=temp/clang-main-10e0a315 ;;
    ubuntu22) build=temp/baseline-clang22 ;;
    *) printf 'Использование: %s [main|ubuntu22] [perf|throughput|prepare]\n' "$0" >&2; exit 2 ;;
esac
mode=${2:-perf}
cpu=1 # P-core, см. /sys/bus/event_source/devices/cpu_core/cpus
messages=${ITCH_MESSAGES:-1000000}
source=tools/itch/sample.itch
input=temp/itch-prefix-$messages.itch
mkdir -p temp

python3 - "$source" "$input" "$messages" <<'PY'
import sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:3])
count = int(sys.argv[3])
if count <= 0:
    raise SystemExit("ITCH_MESSAGES must be positive")
partial = destination.with_suffix(".partial")
with source.open("rb") as stream, partial.open("wb") as output:
    for index in range(count):
        header = stream.read(2)
        size = int.from_bytes(header, "big")
        payload = stream.read(size)
        if len(header) != 2 or size == 0 or len(payload) != size:
            raise SystemExit(f"Incomplete or invalid ITCH message {index + 1}")
        output.write(header)
        output.write(payload)
partial.replace(destination)
PY
stat -c '%n %s bytes' "$source" "$input"
sha256sum "$source" "$input"
[[ $mode != prepare ]] || exit 0

benchmark=$build/cpptrader-performance-market_manager
[[ -x $benchmark ]]
results=$(mktemp -d "$build/run-$mode.XXXXXX")
printf 'Результаты: %s/%s\n' "$PWD" "$results"
{
    date -Iseconds
    uname -srmo
    lscpu
    printf 'CPU affinity: %s\n' "$cpu"
    printf 'perf_event_paranoid: '
    cat /proc/sys/kernel/perf_event_paranoid
    sha256sum "$benchmark" "$source" "$input"
} > "$results/environment.txt"

case $mode in
    perf)
        # События P-core Intel. Отдельные пробные запуски исключают недоступные события.
        candidates=(
            cpu_core/cycles/u
            cpu_core/mem_load_retired.l3_miss/u
            cpu_core/dtlb_load_misses.walk_completed/u
        )
        available=()
        perf --version | tee -a "$results/environment.txt"
        for event in "${candidates[@]}"; do
            printf 'Проба %s\n' "$event"
            if taskset -c "$cpu" perf stat --no-big-num -x ';' -e "$event" \
                -- "$benchmark" < "$input" > /dev/null 2> "$results/probe-${event//\//_}.txt" &&
                grep -Eq '^[0-9]+;' "$results/probe-${event//\//_}.txt"; then
                available+=("$event")
            else
                cat "$results/probe-${event//\//_}.txt" >&2
            fi
        done
        if [[ ${available[0]:-} != "${candidates[0]}" ]]; then
            printf 'Аппаратное событие cycles недоступно.\n' >&2
            exit 1
        fi
        events=$(IFS=,; printf '%s' "${available[*]}")
        command=(taskset -c "$cpu" perf stat --no-big-num -x ';' -e "$events" -- "$benchmark")
        ;;
    throughput) command=(taskset -c "$cpu" "$benchmark") ;;
    *) printf 'Неизвестный режим: %s\n' "$mode" >&2; exit 2 ;;
esac

{
    printf '%q ' "${command[@]}"
    printf '< %q\n' "$input"
} | tee "$results/command.txt"
cat "$input" > /dev/null
for run in warmup 1 2 3 4 5; do
    "${command[@]}" < "$input" > "$results/run-$run.txt" 2> "$results/perf-$run.txt"
done

python3 - "$results" "$messages" "${events:-}" <<'PY' | tee "$results/summary.tsv"
import re
import statistics
import sys
from pathlib import Path

directory = Path(sys.argv[1])
expected_messages = int(sys.argv[2])
expected_counters = len(sys.argv[3].split(",")) if sys.argv[3] else 0
rows = []
expected_updates = None
counter_names = None
for run in ("warmup", "1", "2", "3", "4", "5"):
    output = (directory / f"run-{run}.txt").read_text()
    labels = ("Errors", "Total ITCH messages", "Total market updates",
              "ITCH message throughput", "Market update throughput")
    values = [re.search(rf"^{label}: (\d+)", output, re.M) for label in labels]
    if not all(values):
        raise SystemExit(f"Missing benchmark values in run {run}")
    errors, messages, updates, msg_s, upd_s = (int(value[1]) for value in values)
    if expected_updates is None:
        expected_updates = updates
    if errors or messages != expected_messages or not updates or updates != expected_updates:
        raise SystemExit(f"Unexpected errors, message or update count in run {run}")
    if run == "warmup":
        continue
    counters = {}
    for line in (directory / f"perf-{run}.txt").read_text().splitlines():
        fields = line.split(";")
        if len(fields) > 2 and fields[2] and not line.startswith("#"):
            if not fields[0].isdigit():
                raise SystemExit(f"Invalid perf counter in run {run}: {line}")
            counters[fields[2]] = int(fields[0]) / updates
    if counter_names is None:
        counter_names = list(counters)
    if len(counters) != expected_counters or list(counters) != counter_names:
        raise SystemExit(f"Different perf counters in run {run}")
    rows.append([msg_s, upd_s, *counters.values()])

print(f"messages={expected_messages}\tupdates={expected_updates}")
print("run", "msg/s", "upd/s", *(f"{event}/update" for event in counter_names), sep="\t")
for idx, row in enumerate(rows, 1):
    print(idx, *(f"{value:.8g}" for value in row), sep="\t")
for label, calculate in (("median", statistics.median), ("min", min), ("max", max)):
    print(label, *(f"{calculate(column):.8g}" for column in zip(*rows)), sep="\t")
PY
