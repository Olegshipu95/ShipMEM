#!/usr/bin/env bash
set -euo pipefail

# sudo apt install git make gcc g++ cmake python3-venv binutils binutils-dev uuid-dev libssl-dev gdb
# python3 -m venv ~/.local/share/shipmem-build
# ~/.local/share/shipmem-build/bin/python -m pip install gil==1.25.0.0
#
# Для повторения с чистой рабочей копии передай --reset-submodule.

case "$#:$*" in
    0:) ;;
    1:--reset-submodule) ;;
    *) printf 'Usage: %s [--reset-submodule]\n' "$0" >&2; exit 2 ;;
esac

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
gil=${GIL:-"$HOME/.local/share/shipmem-build/bin/gil"}
export CC=/usr/bin/gcc CXX=/usr/bin/g++

printf '\n1. Проверка инструментов и состояния ShipMEM\n'
for command in git cmake make ctest readelf gdb "$CC" "$CXX" "$gil"; do
    if ! command -v "$command" >/dev/null; then
        printf 'Не найдена команда %s\n' "$command" >&2
        exit 1
    fi
done
git status --short
git submodule status -- CppTrader
git ls-tree HEAD CppTrader

printf '\n2. Инициализация CppTrader\n'
if [[ ${1:-} == --reset-submodule ]]; then
    git submodule deinit --force -- CppTrader
fi
git submodule update --init --recursive -- CppTrader
cd CppTrader
commit=$(git rev-parse HEAD)
printf 'CppTrader %s\n' "$commit"
if [[ $commit != d9625c83e4d592eff65281b00e3e79348d413eeb || -n $(git status --porcelain) ]]; then
    printf 'Для этого прогона нужна чистая копия CppTrader на d9625c8.\n' >&2
    git status --short >&2
    exit 1
fi
"$CC" --version
"$CXX" --version
cmake --version
uname -srmo
lscpu
stat -c '%n %s bytes' tools/itch/sample.itch

printf '\n3. Загрузка и фиксация зависимостей\n'
cat .gitlinks
"$gil" update

while read -r path revision; do
    if ! git -C "$path" cat-file -e "$revision^{commit}" 2>/dev/null; then
        git -C "$path" fetch origin "$revision"
    fi
    if [[ $(git -C "$path" rev-parse HEAD) != "$revision" ]]; then
        git -C "$path" checkout --detach "$revision"
    fi
    printf '%s  %s\n' "$path" "$(git -C "$path" rev-parse HEAD)"
done <<'DEPENDENCIES'
build 8500742b229fb7ae84d9de20cfb41dedd7fce9ee
cmake 7ce7602bfde7e81152186b697113e971439ec056
modules/Catch2 36c1bc3ef209a649741f36d9913d63451e8d07b5
modules/cpp-optparse b90dd73f1d33fb36d782107c233e8f46e2ee40c3
modules/CppBenchmark b3cfd0abef17a2da603cdf3a54aa4d53eda4d5c6
modules/CppCommon b6b9927fc4cb3a7bcba499d7306961e720bdf59f
modules/CppBenchmark/modules/HdrHistogram 13a13ece0cf9246a36d8379698913fd5208e653f
modules/CppBenchmark/modules/zlib 99623ef7097352da7993ba614161fd6a311e046e
modules/CppCommon/modules/fmt dcdec038abe9d042cf8494c4e371bd73c04cb114
modules/CppCommon/modules/vld 272be15648e29560221b2332821d71280110cc9d
DEPENDENCIES

histogram=modules/CppBenchmark/modules/HdrHistogram
git -C "$histogram" submodule update --init --recursive
git -C "$histogram" submodule status --recursive
[[ $(git -C "$histogram/test/vendor/google/benchmark" rev-parse HEAD) == daff5fead3fbe22c6fc58310ca3f49caf117f185 ]]

printf '\n4. Штатная сборка Release с GCC\n'
cat build/unix.sh build/Unix/01-generate.sh
# При повторном запуске сбрасываем кэш, чтобы вернуть штатные флаги.
if [[ -f temp/CMakeCache.txt ]]; then
    cmake --fresh -S . -B temp -G 'Unix Makefiles' \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PWD/temp/install"
fi
(cd build && ./unix.sh)

benchmark=bin/cpptrader-performance-market_manager
flags=temp/CMakeFiles/cpptrader-performance-market_manager.dir/flags.make
grep -E '^CMAKE_(BUILD_TYPE|CXX_COMPILER|CXX_FLAGS_RELEASE):' temp/CMakeCache.txt
grep '^CXX_FLAGS' "$flags"
sections=$(readelf -SW "$benchmark")
grep -E '\.debug_|\.symtab' <<<"$sections"
if grep -q '\.debug_info' <<<"$sections"; then
    printf 'В штатной сборке неожиданно присутствует .debug_info.\n' >&2
    exit 1
fi
ctest --test-dir temp --no-tests=error -V

printf '\n5. Повторная сборка Release с DWARF\n'
cmake -S . -B temp -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS_RELEASE='-O3 -DNDEBUG -g' \
    -DCMAKE_CXX_FLAGS_RELEASE='-O3 -DNDEBUG -g'
(cd build && ./unix.sh)
grep -E '^CMAKE_(C|CXX)_FLAGS_RELEASE:' temp/CMakeCache.txt
grep '^CXX_FLAGS' "$flags"
sections=$(readelf -SW "$benchmark")
grep -E '\.debug_info[[:space:]]' <<<"$sections"
grep -E '\.debug_line[[:space:]]' <<<"$sections"

printf '\n6. Раскладка типов, тесты и SHA-256\n'
gdb -nx -batch -iex 'set auto-load off' \
    -ex 'ptype /o CppTrader::Matching::OrderNode' \
    -ex 'ptype /o CppTrader::Matching::LevelNode' "$benchmark"
ctest --test-dir temp --no-tests=error -V
sha256sum "$benchmark"
git -C .. status --short
