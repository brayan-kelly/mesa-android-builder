#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

readonly MESA_REPO="${MESA_REPO:-https://gitlab.freedesktop.org/mesa/mesa.git}"
readonly WORK_DIR="${WORK_DIR:-/work}"
readonly OUT_DIR="${OUT_DIR:-/out}"
readonly API_LEVEL="${API_LEVEL:-34}"
readonly ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/opt/android-ndk-r29}"
readonly PACKAGE_NAME="${PACKAGE_NAME:-Mesa-Turnip-AdrenoTools}"
readonly MAGISK_PACKAGE_NAME="Mesa-Turnip-Magisk"
readonly MAGISK_VULKAN_FILENAME="${MAGISK_VULKAN_FILENAME:-vulkan.adreno.so}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

trap 'echo "ERROR: build failed at line $LINENO" >&2' ERR

command -v git >/dev/null || die "git is required"
command -v meson >/dev/null || die "meson is required"
command -v zip >/dev/null || die "zip is required"
command -v readelf >/dev/null || die "readelf is required"
command -v patchelf >/dev/null || die "patchelf is required"
command -v python3 >/dev/null || die "python3 is required"
[[ "$PACKAGE_NAME" =~ ^[A-Za-z0-9]+([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || \
  die "PACKAGE_NAME may contain only letters, numbers, and internal hyphens"
[[ "$MAGISK_VULKAN_FILENAME" =~ ^vulkan\.[A-Za-z0-9_-]+\.so$ ]] || \
  die "MAGISK_VULKAN_FILENAME must look like vulkan.adreno.so"

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
BUILD_DIR="$WORK_DIR/build-android-aarch64"
INSTALL_DIR="$WORK_DIR/install"
PACKAGE_DIR="$WORK_DIR/package"
ZIP_PATH="$OUT_DIR/${PACKAGE_NAME}.${MESA_VERSION}.zip"
MAGISK_PACKAGE_DIR="$WORK_DIR/package-turnip-magisk"
MAGISK_ZIP_PATH="$OUT_DIR/${MAGISK_PACKAGE_NAME}.${MESA_VERSION}.zip"

echo "=== Mesa release: $MESA_TAG ==="
echo "=== Packages: $PACKAGE_NAME and $MAGISK_PACKAGE_NAME ==="
rm -rf "$MESA_SRC" "$BUILD_DIR" "$INSTALL_DIR" "$PACKAGE_DIR" \
  "$MAGISK_PACKAGE_DIR" "$ZIP_PATH" "$MAGISK_ZIP_PATH"

git clone --depth=1 --branch "$MESA_TAG" "$MESA_REPO" "$MESA_SRC"
MESA_COMMIT="$(git -C "$MESA_SRC" rev-parse HEAD)"
echo "=== Mesa commit: $MESA_COMMIT ==="

TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
ANDROID_CLANG="$TOOLCHAIN/bin/aarch64-linux-android${API_LEVEL}-clang"
ANDROID_CLANGXX="$TOOLCHAIN/bin/aarch64-linux-android${API_LEVEL}-clang++"
ANDROID_AR="$TOOLCHAIN/bin/llvm-ar"
ANDROID_STRIP="$TOOLCHAIN/bin/llvm-strip"

[[ -x "$ANDROID_CLANG" ]] || die "missing Android C compiler: $ANDROID_CLANG"
[[ -x "$ANDROID_CLANGXX" ]] || die "missing Android C++ compiler: $ANDROID_CLANGXX"
[[ -x "$ANDROID_AR" ]] || die "missing Android archiver: $ANDROID_AR"
[[ -x "$ANDROID_STRIP" ]] || die "missing Android strip tool: $ANDROID_STRIP"

cat > "$WORK_DIR/android-aarch64.txt" <<EOF
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

echo "=== Configuring upstream Android KGSL Turnip ==="
meson setup "$BUILD_DIR" "$MESA_SRC" \
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
readelf -d "$VULKAN_SO" | grep -Eq 'SONAME.*libvulkan_freedreno\.so' || \
  die "driver SONAME is not libvulkan_freedreno.so: $VULKAN_SO"

mkdir -p "$PACKAGE_DIR"
cp -L "$VULKAN_SO" "$PACKAGE_DIR/libvulkan_freedreno.so"

cat > "$PACKAGE_DIR/meta.json" <<EOF
{
  "schemaVersion": 1,
  "name": "Mesa Turnip $MESA_VERSION",
  "description": "Upstream Mesa Turnip Vulkan driver for Qualcomm Adreno GPUs; tag $MESA_TAG, commit $MESA_COMMIT",
  "author": "Mesa Project",
  "packageVersion": "1",
  "vendor": "Mesa",
  "driverVersion": "Mesa $MESA_VERSION",
  "mesaTag": "$MESA_TAG",
  "mesaCommit": "$MESA_COMMIT",
  "apiLevel": $API_LEVEL,
  "androidNdk": "r29",
  "minApi": 28,
  "libraryName": "libvulkan_freedreno.so"
}
EOF

python3 -m json.tool "$PACKAGE_DIR/meta.json" >/dev/null || \
  die "generated meta.json is invalid"
touch -d '1970-01-01 00:00:00 UTC' "$PACKAGE_DIR/libvulkan_freedreno.so" "$PACKAGE_DIR/meta.json"
rm -f "$ZIP_PATH"
(cd "$PACKAGE_DIR" && zip -X -9 "$ZIP_PATH" libvulkan_freedreno.so meta.json)

[[ "$(unzip -Z1 "$ZIP_PATH" | sort)" == $'libvulkan_freedreno.so\nmeta.json' ]] || \
  die "unexpected AdrenoTools ZIP contents"

MAGISK_LIBRARY="$MAGISK_PACKAGE_DIR/system/vendor/lib64/hw/$MAGISK_VULKAN_FILENAME"
mkdir -p "${MAGISK_LIBRARY%/*}"
cp -L "$VULKAN_SO" "$MAGISK_LIBRARY"
patchelf --set-soname "$MAGISK_VULKAN_FILENAME" "$MAGISK_LIBRARY"
readelf -h "$MAGISK_LIBRARY" | grep -q 'AArch64' || \
  die "Magisk driver is not an AArch64 ELF: $MAGISK_LIBRARY"
readelf -d "$MAGISK_LIBRARY" | grep -Eq "SONAME.*${MAGISK_VULKAN_FILENAME//./\\.}" || \
  die "Magisk driver SONAME does not match $MAGISK_VULKAN_FILENAME"

cat > "$MAGISK_PACKAGE_DIR/module.prop" <<EOF
id=mesa-turnip
name=Mesa Turnip
version=$MESA_VERSION
versionCode=$MESA_VERSION_CODE
author=Mesa Project
description=Experimental upstream Mesa Turnip Vulkan driver; HAL filename: $MAGISK_VULKAN_FILENAME
EOF
cat > "$MAGISK_PACKAGE_DIR/README.txt" <<EOF
Mesa Turnip Magisk module
Mesa tag: $MESA_TAG
Mesa commit: $MESA_COMMIT
Vulkan HAL filename: $MAGISK_VULKAN_FILENAME

This is an experimental global Vulkan override. Prefer the AdrenoTools
package with per-app driver selection when testing games or Android apps.
Global replacement can affect Android HWUI and system services. Do not enable
this module together with another module that overlays the same Vulkan HAL.

The Vulkan HAL filename is device-specific. Override MAGISK_VULKAN_FILENAME
when building this package. Keep a recovery path and disable this module from
Magisk Safe Mode if Android fails to boot.
EOF

touch -d '1970-01-01 00:00:00 UTC' "$MAGISK_PACKAGE_DIR/module.prop" "$MAGISK_PACKAGE_DIR/README.txt" "$MAGISK_LIBRARY"
(cd "$MAGISK_PACKAGE_DIR" && zip -X -9 -r "$MAGISK_ZIP_PATH" module.prop README.txt system)
unzip -Z1 "$MAGISK_ZIP_PATH" | grep -qx 'module.prop' || \
  die "Magisk module.prop is missing"
unzip -Z1 "$MAGISK_ZIP_PATH" | grep -qx "system/vendor/lib64/hw/$MAGISK_VULKAN_FILENAME" || \
  die "Magisk Vulkan library is missing"

(cd "$OUT_DIR" && sha256sum "$(basename "$ZIP_PATH")" "$(basename "$MAGISK_ZIP_PATH")" > SHA256SUMS.txt)
(cd "$OUT_DIR" && sha512sum "$(basename "$ZIP_PATH")" "$(basename "$MAGISK_ZIP_PATH")" > SHA512SUMS.txt)
echo "=== Build complete ==="
cat "$OUT_DIR/SHA256SUMS.txt"
cat "$OUT_DIR/SHA512SUMS.txt"
