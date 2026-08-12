#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -Eeuo pipefail
source /opt/mesa-build-common.sh

trap 'echo "ERROR: build failed at line $LINENO" >&2' ERR
command -v patchelf >/dev/null || die "patchelf is required for the Magisk package"

MAGISK_VULKAN_FILENAME="${MAGISK_VULKAN_FILENAME:-vulkan.adreno.so}"
[[ "$MAGISK_VULKAN_FILENAME" =~ ^vulkan\.[A-Za-z0-9_-]+\.so$ ]] || \
  die "MAGISK_VULKAN_FILENAME must look like vulkan.adreno.so"

mesa_prepare
BUILD_DIR="$WORK_DIR/build-android-aarch64-turnip-magisk"
INSTALL_DIR="$WORK_DIR/install-turnip-magisk"
PACKAGE_DIR="$WORK_DIR/package-turnip-magisk"
ZIP_PATH="$OUT_DIR/Mesa-Turnip-Magisk.$MESA_VERSION.zip"
rm -rf "$BUILD_DIR" "$INSTALL_DIR" "$PACKAGE_DIR" "$ZIP_PATH"

echo "=== Configuring upstream Android KGSL Turnip for Magisk ==="
meson setup "$BUILD_DIR" "$MESA_SRC" \
  --prefix "$INSTALL_DIR" \
  "${COMMON_MESON_OPTIONS[@]}" \
  -Degl=disabled \
  -Dgallium-drivers= \
  -Dvulkan-drivers=freedreno \
  -Dvulkan-beta=true \
  -Dfreedreno-kmds=kgsl
meson compile -C "$BUILD_DIR"
meson install -C "$BUILD_DIR"

TURNIP_SO="$INSTALL_DIR/lib/libvulkan_freedreno.so"
[[ -f "$TURNIP_SO" ]] || die "Mesa did not install $TURNIP_SO"
readelf -h "$TURNIP_SO" | grep -q 'AArch64' || die "Turnip is not an AArch64 ELF"

MODULE_LIBRARY="$PACKAGE_DIR/system/vendor/lib64/hw/$MAGISK_VULKAN_FILENAME"
mkdir -p "${MODULE_LIBRARY%/*}"
cp -L "$TURNIP_SO" "$MODULE_LIBRARY"
patchelf --set-soname "$MAGISK_VULKAN_FILENAME" "$MODULE_LIBRARY"

cat > "$PACKAGE_DIR/module.prop" <<EOF
id=mesa-turnip
name=Mesa Turnip
version=$MESA_VERSION
versionCode=$MESA_VERSION_CODE
author=Mesa Project
description=Experimental upstream Mesa Turnip Vulkan driver; HAL filename: $MAGISK_VULKAN_FILENAME
EOF
cat > "$PACKAGE_DIR/README.txt" <<EOF
Mesa Turnip Magisk module
Mesa tag: $MESA_TAG
Mesa commit: $MESA_COMMIT
Vulkan HAL filename: $MAGISK_VULKAN_FILENAME

The Vulkan HAL filename is device-specific. Override MAGISK_VULKAN_FILENAME
when building this package. Keep a recovery path and disable this module from
Magisk Safe Mode if Android fails to boot.
EOF

(cd "$PACKAGE_DIR" && zip -9 -r "$ZIP_PATH" module.prop README.txt system)
unzip -Z1 "$ZIP_PATH" | grep -qx 'module.prop' || die "module.prop is missing"
unzip -Z1 "$ZIP_PATH" | grep -qx "system/vendor/lib64/hw/$MAGISK_VULKAN_FILENAME" || \
  die "Magisk Vulkan library is missing"

checksum_outputs "$ZIP_PATH"
