#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -Eeuo pipefail
source /opt/mesa-build-common.sh

trap 'echo "ERROR: build failed at line $LINENO" >&2' ERR

FREEADRENO_KMDS="${FREEADRENO_KMDS:-msm}"
[[ "$FREEADRENO_KMDS" =~ ^(msm|kgsl|virtio)(,(msm|kgsl|virtio))*$ ]] || \
  die "FREEADRENO_KMDS must be a comma-separated list of msm, kgsl, or virtio"

mesa_prepare
BUILD_DIR="$WORK_DIR/build-android-aarch64-freeadreno"
INSTALL_DIR="$WORK_DIR/install-freeadreno"
PACKAGE_DIR="$WORK_DIR/package-freeadreno-magisk"
ZIP_PATH="$OUT_DIR/Mesa-FreeAdreno-Magisk.$MESA_VERSION.zip"
rm -rf "$BUILD_DIR" "$INSTALL_DIR" "$PACKAGE_DIR" "$ZIP_PATH"

# Android does not use Mesa's XML configuration path. Freedreno's optional
# decode tooling can otherwise trigger an unnecessary libarchive download.
(cd "$MESA_SRC" && meson subprojects download libdrm)

echo "=== Configuring experimental Android FreeAdreno GLES for Magisk ==="
if [[ "$FREEADRENO_KMDS" == *kgsl* ]]; then
  echo "WARNING: upstream Freedreno Gallium does not support KGSL; use msm for DRM-based systems" >&2
fi

meson setup "$BUILD_DIR" "$MESA_SRC" \
  --prefix "$INSTALL_DIR" \
  --wrap-mode=nodownload \
  "${COMMON_MESON_OPTIONS[@]}" \
  -Dexpat=disabled \
  -Dxmlconfig=disabled \
  -Degl=enabled \
  -Dgles1=enabled \
  -Dgles2=enabled \
  -Dopengl=false \
  -Dglx=disabled \
  -Dgbm=disabled \
  -Dgallium-drivers=freedreno \
  -Dvulkan-drivers= \
  -Dfreedreno-kmds="$FREEADRENO_KMDS" \
  -Degl-lib-suffix=_mesa \
  -Dgles-lib-suffix=_mesa \
  -Dunversion-libgallium=true
meson compile -C "$BUILD_DIR"
meson install -C "$BUILD_DIR"

for library in libEGL_mesa.so libGLESv1_CM_mesa.so libGLESv2_mesa.so libgallium_dri.so; do
  [[ -f "$INSTALL_DIR/lib/$library" ]] || die "Mesa did not install $INSTALL_DIR/lib/$library"
  readelf -h "$INSTALL_DIR/lib/$library" | grep -q 'AArch64' || \
    die "FreeAdreno library is not an AArch64 ELF: $library"
done

mkdir -p "$PACKAGE_DIR/system/vendor/lib64/egl" "$PACKAGE_DIR/system/vendor/lib64/dri"
cp -L "$INSTALL_DIR/lib/libEGL_mesa.so" "$PACKAGE_DIR/system/vendor/lib64/egl/"
cp -L "$INSTALL_DIR/lib/libGLESv1_CM_mesa.so" "$PACKAGE_DIR/system/vendor/lib64/egl/"
cp -L "$INSTALL_DIR/lib/libGLESv2_mesa.so" "$PACKAGE_DIR/system/vendor/lib64/egl/"
cp -L "$INSTALL_DIR/lib/libgallium_dri.so" "$PACKAGE_DIR/system/vendor/lib64/"
if [[ -f "$INSTALL_DIR/lib/libglapi.so" ]]; then
  cp -L "$INSTALL_DIR/lib/libglapi.so" "$PACKAGE_DIR/system/vendor/lib64/"
fi

shopt -s nullglob
DRI_LIBRARIES=("$INSTALL_DIR"/lib/dri/*_dri.so)
shopt -u nullglob
if ((${#DRI_LIBRARIES[@]} > 0)); then
  cp -L "${DRI_LIBRARIES[@]}" "$PACKAGE_DIR/system/vendor/lib64/dri/"
fi

cat > "$PACKAGE_DIR/module.prop" <<EOF
id=mesa-freeadreno
name=Mesa FreeAdreno GLES
version=$MESA_VERSION
versionCode=$MESA_VERSION_CODE
author=Mesa Project
description=Experimental upstream Mesa Freedreno GLES/EGL driver; KMDs: $FREEADRENO_KMDS
EOF
cat > "$PACKAGE_DIR/README.txt" <<EOF
Mesa FreeAdreno Magisk module
Mesa tag: $MESA_TAG
Mesa commit: $MESA_COMMIT
Freedreno KMDs: $FREEADRENO_KMDS

This package is experimental. Upstream Mesa states that Freedreno Gallium
does not support KGSL. The default build targets msm/DRM systems and is not a
drop-in replacement for a stock KGSL GLES vendor driver.
EOF

(cd "$PACKAGE_DIR" && zip -9 -r "$ZIP_PATH" module.prop README.txt system)
unzip -Z1 "$ZIP_PATH" | grep -qx 'module.prop' || die "module.prop is missing"
unzip -Z1 "$ZIP_PATH" | grep -qx 'system/vendor/lib64/egl/libGLESv2_mesa.so' || \
  die "FreeAdreno GLES library is missing"

checksum_outputs "$ZIP_PATH"
