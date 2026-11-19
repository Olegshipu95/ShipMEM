#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
mkdir -p llvm-libcxx-22/packages
cd llvm-libcxx-22/packages
version=1:22.1.2-1ubuntu1
packages=(libc++-22-dev libc++abi-22-dev libc++1 libc++abi1 llvm-libunwind1)
apt-get download "${packages[@]/%/=$version}"
for package in "${packages[@]}"; do
    dpkg-deb -x "${package}_${version/:/%3a}_amd64.deb" ../sysroot
done
