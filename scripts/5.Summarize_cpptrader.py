#!/usr/bin/env python3
"""Summarize paired CppTrader and perf-stat logs from the diagnostic series."""

import argparse
import re
import statistics
from pathlib import Path


METRICS = (
    ("Сообщений/с (млн)", 3),
    ("Обновлений/с (млн)", 3),
    ("Циклы на обновление", 2),
    ("Загрузки с промахом L3 на обновление", 5),
    ("Обходы dTLB на обновление", 5),
    ("Полное время процесса, мс", 3),
    ("Время в пользовательском режиме, мс", 3),
    ("Время в ядре, мс", 3),
    ("task-clock, мс", 3),
    ("Переключения контекста", 2),
    ("Миграции CPU", 2),
    ("Циклы на инструкцию", 4),
    ("Оценка частоты, ГГц", 3),
)


def read_number(path, content, pattern, label, convert=float):
    match = re.search(pattern, content, re.MULTILINE)
    if match is None:
        raise ValueError(f"{path}: нет числового значения для {label}")
    return convert(match[1].replace(",", "."))


def read_run(directory, run):
    bench_path = directory / f"bench-{run}.txt"
    perf_path = directory / f"perf-{run}.txt"
    bench = bench_path.read_text()
    perf = perf_path.read_text()

    def bench_value(label):
        return read_number(bench_path, bench, rf"^{label}: (\d+)\b", label, int)

    def counter(event):
        pattern = rf"^[ \t]*(\d+)[ \t]+{re.escape(event)}(?::u)?(?=\s|$)"
        return read_number(perf_path, perf, pattern, event, int)

    def seconds(label):
        pattern = rf"^[ \t]*(\d+[.,]\d+)[ \t]+seconds {re.escape(label)}\b"
        return read_number(perf_path, perf, pattern, label)

    updates = bench_value("Total market updates")
    if (bench_value("Errors"), bench_value("Total ITCH messages"), updates) != (
        0, 1563071, 254853
    ):
        raise ValueError(f"{bench_path}: ожидались 0 ошибок, 1563071 сообщение и 254853 обновления")

    cycles = counter("cpu_core/cycles/u")
    instructions = counter("cpu_core/instructions/u")
    user = seconds("user")
    if min(cycles, instructions, user) <= 0:
        raise ValueError(f"{perf_path}: циклы, инструкции и время user должны быть положительными")

    return (
        bench_value("ITCH message throughput") / 1e6,
        bench_value("Market update throughput") / 1e6,
        cycles / updates,
        counter("cpu_core/mem_load_retired.l3_miss/u") / updates,
        counter("cpu_core/dtlb_load_misses.walk_completed/u") / updates,
        seconds("time elapsed") * 1000,
        user * 1000,
        seconds("sys") * 1000,
        read_number(perf_path, perf, r"^[ \t]*(\d+(?:[.,]\d+)?)[ \t]+msec[ \t]+task-clock(?::u)?\b", "task-clock"),
        counter("context-switches"),
        counter("cpu-migrations"),
        cycles / instructions,
        cycles / user / 1e9,
    )


def summary(column, precision):
    q1, _, q3 = statistics.quantiles(column, n=4, method="inclusive")
    median = statistics.median(column)
    return f"{median:.{precision}f} [{q1:.{precision}f}; {q3:.{precision}f}]".replace(".", ",")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("isolated", type=Path, help="каталог серии с изоляцией")
    parser.add_argument("nonisolated", type=Path, nargs="?", help="каталог серии без изоляции")
    parser.add_argument("--runs", type=int, default=100, help="число измеряемых прогонов")
    args = parser.parse_args()
    if args.runs < 2:
        parser.error("--runs должно быть не меньше 2")

    directories = [args.isolated]
    headers = ["Метрика", "С изоляцией"]
    if args.nonisolated is not None:
        directories.append(args.nonisolated)
        headers.append("Без изоляции")
    try:
        series = [
            list(zip(*(read_run(directory, run) for run in range(1, args.runs + 1))))
            for directory in directories
        ]
    except (OSError, ValueError) as error:
        parser.exit(1, f"Ошибка: {error}\n")

    print("| " + " | ".join(headers) + " |")
    print("|" + "|".join("---" for _ in headers) + "|")
    for index, (label, precision) in enumerate(METRICS):
        values = [summary(columns[index], precision) for columns in series]
        print("| " + " | ".join([label, *values]) + " |")


if __name__ == "__main__":
    main()
