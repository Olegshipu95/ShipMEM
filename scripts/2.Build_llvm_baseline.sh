#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
revision=10e0a315ad623811298aaa2617027e6ea0f002b8
url=https://github.com/llvm/llvm-project.git
llvm_source=${LLVM_SOURCE:-"$PWD/../llvm-baseline-10e0a315"}
llvm_build=${LLVM_BUILD:-"$PWD/../llvm-build-10e0a315"}

# Команда, которой была зафиксирована вершина main:
# git ls-remote https://github.com/llvm/llvm-project.git refs/heads/main
if [[ ! -d $llvm_source/.git ]]; then
    git init "$llvm_source"
    git -C "$llvm_source" remote add origin "$url"
fi
if ! git -C "$llvm_source" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$llvm_source" fetch --depth=1 "$url" "$revision"
    git -C "$llvm_source" checkout --detach FETCH_HEAD
fi
[[ $(git -C "$llvm_source" rev-parse HEAD) == "$revision" ]]
[[ -z $(git -C "$llvm_source" status --porcelain) ]]
git -C "$llvm_source" log -1 --format='%H %cI %s'

/usr/bin/clang-22 --version
/usr/bin/clang++-22 --version
cmake -S "$llvm_source/llvm" -B "$llvm_build" -G 'Unix Makefiles' \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=/usr/bin/clang-22 \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++-22 \
    -DLLVM_ENABLE_PROJECTS=clang \
    -DLLVM_TARGETS_TO_BUILD=X86 \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF
cmake --build "$llvm_build" --target clang clang-resource-headers --parallel "${LLVM_JOBS:-12}"

"$llvm_build/bin/clang" --version
"$llvm_build/bin/clang++" --version
sha256sum "$(realpath "$llvm_build/bin/clang")"
