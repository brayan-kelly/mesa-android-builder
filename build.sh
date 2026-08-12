#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

readonly MESA_REPO="${MESA_REPO:-https://gitlab.freedesktop.org/mesa/mesa.git}"
readonly WORK_DIR="${WORK_DIR:-/work}"
readonly OUT_DIR="${OUT_DIR:-/out}"
readonly API_LEVEL="${API_LEVEL:-34}"
readonly ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/opt/android-ndk-r29}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

trap 'echo "ERROR: build failed at line $LINENO" >&2' ERR

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
MESA_SRC="$WORK_DIR/mesa"
BUILD_DIR="$WORK_DIR/build-android-aarch64"
INSTALL_DIR="$WORK_DIR/install"
PACKAGE_DIR="$WORK_DIR/package"
ZIP_PATH="$OUT_DIR/Mesa-Turnip-${MESA_VERSION}.zip"

echo "=== Mesa release: $MESA_TAG ==="
rm -rf "$MESA_SRC" "$BUILD_DIR" "$INSTALL_DIR" "$PACKAGE_DIR"

git clone --depth=1 --branch "$MESA_TAG" "$MESA_REPO" "$MESA_SRC"
MESA_COMMIT="$(git -C "$MESA_SRC" rev-parse HEAD)"
echo "=== Mesa commit: $MESA_COMMIT ==="

TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
ANDROID_CLANG="$TOOLCHAIN/bin/aarch64-linux-android${API_LEVEL}-clang"
ANDROID_CLANGXX="$TOOLCHAIN/bin/aarch64-linux-android${API_LEVEL}-clang++"

[[ -x "$ANDROID_CLANG" ]] || die "missing Android C compiler: $ANDROID_CLANG"
[[ -x "$ANDROID_CLANGXX" ]] || die "missing Android C++ compiler: $ANDROID_CLANGXX"

cat > "$WORK_DIR/android-aarch64.txt" <<EOF
[constants]
ndk_path = '$ANDROID_NDK_HOME'
toolchain_path = ndk_path / 'toolchains/llvm/prebuilt/linux-x86_64'

[binaries]
ar = toolchain_path / 'bin/aarch64-linux-android-ar'
c = [toolchain_path / 'bin/aarch64-linux-android${API_LEVEL}-clang']
cpp = [toolchain_path / 'bin/aarch64-linux-android${API_LEVEL}-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '--start-no-unused-arguments', '-static-libstdc++', '--end-no-unused-arguments']
c_ld = 'lld'
cpp_ld = 'lld'
strip = toolchain_path / 'bin/aarch64-linux-android-strip'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

echo "=== Configuring upstream Android KGSL Turnip ==="
meson setup "$BUILD_DIR" \
  --cross-file "$WORK_DIR/android-aarch64.txt" \
  --prefix "$INSTALL_DIR" \
  -Dbuildtype=release \
  -Dstrip=true \
  -Dplatforms=android \
  -Dplatform-sdk-version="$API_LEVEL" \
  -Dandroid-stub=true \
  -Dandroid-libbacktrace=disabled \
  -Degl=disabled \
  -Dgallium-drivers= \
  -Dvulkan-drivers=freedreno \
  -Dvulkan-beta=true \
  -Dfreedreno-kmds=kgsl \
  -Dallow-fallback-for=libdrm \
  -Dvideo-codecs=

meson compile -C "$BUILD_DIR"
meson install -C "$BUILD_DIR"

VULKAN_SO="$INSTALL_DIR/lib/libvulkan_freedreno.so"
[[ -f "$VULKAN_SO" ]] || die "Mesa did not install $VULKAN_SO"

readelf -h "$VULKAN_SO" | grep -q 'AArch64' || \
  die "driver is not an AArch64 ELF: $VULKAN_SO"

mkdir -p "$PACKAGE_DIR"
cp -L "$VULKAN_SO" "$PACKAGE_DIR/libvulkan_freedreno.so"

cat > "$PACKAGE_DIR/meta.json" <<EOF
{
  "schemaVersion": 1,
  "name": "Mesa Turnip",
  "description": "Upstream Mesa Turnip Vulkan driver for Qualcomm Adreno GPUs",
  "author": "Mesa Project",
  "packageVersion": "$MESA_VERSION",
  "vendor": "Mesa",
  "driverVersion": "Mesa $MESA_VERSION",
  "mesaTag": "$MESA_TAG",
  "mesaCommit": "$MESA_COMMIT",
  "minApi": 28,
  "libraryName": "libvulkan_freedreno.so"
}
EOF

rm -f "$ZIP_PATH"
(cd "$PACKAGE_DIR" && zip -9 "$ZIP_PATH" libvulkan_freedreno.so meta.json)

[[ "$(unzip -Z1 "$ZIP_PATH" | sort)" == $'libvulkan_freedreno.so\nmeta.json' ]] || \
  die "unexpected AdrenoTools ZIP contents"

sha256sum "$ZIP_PATH" > "$OUT_DIR/SHA256SUMS.txt"
echo "=== Build complete ==="
cat "$OUT_DIR/SHA256SUMS.txt"
