#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

MESA_REPO="${MESA_REPO:-https://gitlab.freedesktop.org/mesa/mesa.git}"
WORK_DIR="${WORK_DIR:-/work}"
OUT_DIR="${OUT_DIR:-/out}"
API_LEVEL="${API_LEVEL:-34}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/opt/android-ndk-r29}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

mesa_prepare() {
  command -v git >/dev/null || die "git is required"
  command -v meson >/dev/null || die "meson is required"
  command -v zip >/dev/null || die "zip is required"
  command -v readelf >/dev/null || die "readelf is required"
  mkdir -p "$WORK_DIR" "$OUT_DIR"

  if [[ -n "${MESA_TAG:-}" ]]; then
    [[ "$MESA_TAG" =~ ^mesa-[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
      die "MESA_TAG must be a final release tag such as mesa-26.2.0"
  else
    echo "=== Discovering latest stable Mesa release ==="
    MESA_TAG="$(
      git ls-remote --tags --refs "$MESA_REPO" \
        | awk -F/ '$NF ~ /^mesa-[0-9]+\.[0-9]+\.[0-9]+$/ { print $NF }' \
        | sort -V \
        | tail -n 1
    )"
    [[ -n "$MESA_TAG" ]] || die "could not discover a stable Mesa release tag"
  fi

  MESA_VERSION="${MESA_TAG#mesa-}"
  MESA_VERSION_CODE="$(awk -F. '{ printf "%d%02d%02d", $1, $2, $3 }' <<< "$MESA_VERSION")"
  MESA_SRC="$WORK_DIR/mesa"
  rm -rf "$MESA_SRC"
  git clone --depth=1 --branch "$MESA_TAG" "$MESA_REPO" "$MESA_SRC"
  MESA_COMMIT="$(git -C "$MESA_SRC" rev-parse HEAD)"

  TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
  ANDROID_CLANG="$TOOLCHAIN/bin/aarch64-linux-android${API_LEVEL}-clang"
  ANDROID_CLANGXX="$TOOLCHAIN/bin/aarch64-linux-android${API_LEVEL}-clang++"
  ANDROID_AR="$TOOLCHAIN/bin/llvm-ar"
  ANDROID_STRIP="$TOOLCHAIN/bin/llvm-strip"
  [[ -x "$ANDROID_CLANG" ]] || die "missing Android C compiler: $ANDROID_CLANG"
  [[ -x "$ANDROID_CLANGXX" ]] || die "missing Android C++ compiler: $ANDROID_CLANGXX"
  [[ -x "$ANDROID_AR" ]] || die "missing Android archiver: $ANDROID_AR"
  [[ -x "$ANDROID_STRIP" ]] || die "missing Android strip tool: $ANDROID_STRIP"

  CROSS_FILE="$WORK_DIR/android-aarch64.txt"
  cat > "$CROSS_FILE" <<EOF
[constants]
ndk_path = '$ANDROID_NDK_HOME'
toolchain_path = ndk_path / 'toolchains/llvm/prebuilt/linux-x86_64'

[binaries]
ar = toolchain_path / 'bin/llvm-ar'
c = [toolchain_path / 'bin/aarch64-linux-android${API_LEVEL}-clang']
cpp = [toolchain_path / 'bin/aarch64-linux-android${API_LEVEL}-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '--start-no-unused-arguments', '-static-libstdc++', '--end-no-unused-arguments']
c_ld = 'lld'
cpp_ld = 'lld'
strip = toolchain_path / 'bin/llvm-strip'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

  COMMON_MESON_OPTIONS=(
    --cross-file "$CROSS_FILE"
    -Dbuildtype=release
    -Dstrip=true
    -Dplatforms=android
    -Dplatform-sdk-version="$API_LEVEL"
    -Dandroid-stub=true
    -Dandroid-libbacktrace=disabled
    -Dallow-fallback-for=libdrm
    -Dvideo-codecs=
  )

  echo "=== Mesa release: $MESA_TAG ==="
  echo "=== Mesa commit: $MESA_COMMIT ==="
}

checksum_outputs() {
  local packages=("$@")
  if ((${#packages[@]} == 0)); then
    shopt -s nullglob
    packages=("$OUT_DIR"/*.zip)
    shopt -u nullglob
  fi
  ((${#packages[@]} > 0)) || die "no packages were produced"
  local package_names=()
  local package
  for package in "${packages[@]}"; do
    package_names+=("${package##*/}")
  done
  (cd "$OUT_DIR" && sha256sum "${package_names[@]}" > SHA256SUMS.txt)
  (cd "$OUT_DIR" && sha512sum "${package_names[@]}" > SHA512SUMS.txt)
  cat "$OUT_DIR/SHA256SUMS.txt"
  cat "$OUT_DIR/SHA512SUMS.txt"
}
