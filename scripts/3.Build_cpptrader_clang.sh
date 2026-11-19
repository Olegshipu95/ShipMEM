#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../CppTrader"
case ${1:-main} in
    main)
        llvm_build=${LLVM_BUILD:-"$PWD/../../llvm-build-10e0a315"}
        cc=$llvm_build/bin/clang
        cxx=$llvm_build/bin/clang++
        build=temp/clang-main-10e0a315
        ;;
    ubuntu22)
        cc=/usr/bin/clang-22
        cxx=/usr/bin/clang++-22
        build=temp/baseline-clang22
        ;;
    *) printf 'Использование: %s [main|ubuntu22]\n' "$0" >&2; exit 2 ;;
esac

[[ $(git rev-parse HEAD) == d9625c83e4d592eff65281b00e3e79348d413eeb ]]
[[ -z $(git status --porcelain) ]]
"$cc" --version
"$cxx" --version
if [[ ${1:-main} == main ]]; then
    "$cc" --version | grep -F 10e0a315ad623811298aaa2617027e6ea0f002b8
fi
sha256sum "$(realpath "$cc")"

libcxx=$(realpath "$PWD/../../llvm-libcxx-22/sysroot/usr/lib")
libdir=$libcxx/x86_64-linux-gnu
[[ -f $libcxx/llvm-22/include/c++/v1/string && -f $libdir/libc++.so ]]

# Штатный unix.sh использует temp и bin. Отдельный каталог сохраняет сборку GCC.
cmake -S . -B "$build" -G 'Unix Makefiles' \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$cc" -DCMAKE_CXX_COMPILER="$cxx" \
    -DCMAKE_C_FLAGS_RELEASE='-O3 -DNDEBUG -g' \
    -DCMAKE_CXX_FLAGS_RELEASE='-O3 -DNDEBUG -g' \
    -DCMAKE_CXX_FLAGS="-isystem $libcxx/llvm-22/include/c++/v1" \
    -DCMAKE_EXE_LINKER_FLAGS="-L$libdir -Wl,--disable-new-dtags,-rpath,$libdir" \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build "$build" --parallel "${CPPTRADER_JOBS:-6}" \
    --target cpptrader-performance-market_manager cpptrader-tests
ctest --test-dir "$build" --no-tests=error -V

benchmark=$build/cpptrader-performance-market_manager
grep -E '^CMAKE_(BUILD_TYPE|CXX_COMPILER|CXX_FLAGS_RELEASE):' "$build/CMakeCache.txt"
grep '^CXX_FLAGS' "$build/CMakeFiles/cpptrader-performance-market_manager.dir/flags.make"
readelf -SW "$benchmark" | grep -E '\.debug_(info|line)[[:space:]]'
gdb -nx -batch -iex 'set auto-load off' \
    -ex 'ptype /o CppTrader::Matching::OrderNode' \
    -ex 'ptype /o CppTrader::Matching::LevelNode' "$benchmark"
sha256sum "$benchmark"
