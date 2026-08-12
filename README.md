# Mesa Turnip Android Builder

GitHub Actions project for building the latest official stable Mesa Turnip Vulkan driver for Android ARM64 devices using the KGSL backend.

The build selects the newest final `mesa-X.Y.Z` tag from upstream Mesa at runtime. Release candidates, beta tags, development branches, and external patch sets are excluded.

## Output

Each successful workflow produces:

```text
Mesa-Turnip-Emulators.<mesa-version>.zip
SHA256SUMS.txt
SHA512SUMS.txt
```

The driver ZIP is an AdrenoTools-compatible flat package containing:

```text
libvulkan_freedreno.so
meta.json
```

The workflow also has a separate job for the Magisk package:

```text
Mesa-Turnip-Magisk.<mesa-version>.zip
```

It is uploaded as a separate GitHub Actions artifact. No package installs
anything on a device automatically.

## Build configuration

The build uses the upstream Mesa Android configuration:

```text
platforms=android
platform-sdk-version=34
android-stub=true
gallium-drivers=
vulkan-drivers=freedreno
freedreno-kmds=kgsl
```

See the [Mesa Android build documentation](https://docs.mesa3d.org/android.html) for the upstream configuration and the [Freedreno documentation](https://docs.mesa3d.org/drivers/freedreno.html) for hardware support information.

## GitHub Actions

Push to `main`, open a pull request against `main`, or start the `Build Mesa Turnip driver` workflow manually. The workflow:

1. Builds the Docker image.
2. Discovers the newest stable Mesa tag.
3. Cross-compiles Turnip with Android NDK r29.
4. Validates that the result is an AArch64 ELF shared library.
5. Creates and validates the AdrenoTools ZIP.
6. Uploads the package ZIP and SHA-256/SHA-512 checksum files as an artifact.

The `build-turnip-magisk` job repeats the Turnip build and packages it as a
Magisk module under `system/vendor/lib64/hw/`. The Vulkan HAL filename is
device-specific; the workflow default is `vulkan.adreno.so`, and local builds
can override it with `MAGISK_VULKAN_FILENAME`.

## Local build

Docker is required. From the repository root:

```bash
mkdir -p out
docker build -t mesa-turnip-builder .
docker run --rm -v "$PWD/out:/out" mesa-turnip-builder
```

The build downloads the newest stable Mesa release during the container run, so the result is tied to the upstream release available at that time. The selected tag and commit are stored in `meta.json`.

To reproduce a specific final release:

```bash
docker run --rm \
  -e MESA_TAG=mesa-26.2.0 \
  -e PACKAGE_NAME=Mesa-Turnip-Emulators \
  -v "$PWD/out:/out" \
  mesa-turnip-builder
```

Package names use the format `<package>.<mesa-version>.zip`.

Build the Turnip Magisk module separately:

```bash
docker run --rm \
  --entrypoint /opt/build-turnip-magisk.sh \
  -e MESA_TAG=mesa-26.2.0 \
  -e MAGISK_VULKAN_FILENAME=vulkan.adreno.so \
  -v "$PWD/out:/out" \
  mesa-turnip-builder
```

The build writes its package and `SHA256SUMS.txt`/`SHA512SUMS.txt` into `out/`.

### Creating a GitHub release

Push a tag matching the upstream Mesa release tag to build that exact Mesa
version and publish a GitHub release:

```bash
git tag -s mesa-26.2.0 -m "release Mesa Turnip mesa-26.2.0"
git push origin mesa-26.2.0
```

The release contains the AdrenoTools ZIP, `SHA256SUMS.txt`, and
`SHA512SUMS.txt`. Normal pushes to `main` build and upload workflow artifacts
without creating a release.

## Device compatibility

A successful compilation does not guarantee that a driver will initialize on every Qualcomm device. Compatibility depends on the GPU ID, Android version, KGSL implementation, firmware, loader, and the upstream Mesa release.

Before testing on a rooted development device, record:

```bash
adb shell getprop ro.build.version.sdk
adb shell cat /sys/class/kgsl/kgsl-3d0/gpu_model
adb shell cat /sys/class/kgsl/kgsl-3d0/gpu_id
```

For a Turnip Magisk package, first identify the stock Vulkan HAL filename:

```bash
adb shell find /vendor/lib64/hw -maxdepth 1 -type f -name 'vulkan*.so' -print
```

Pass the matching filename as `MAGISK_VULKAN_FILENAME` when building. Use a
recovery path and keep the stock vendor driver available. Do not flash an
untested driver on a production device.

## Scope and licensing

The builder scripts, Dockerfile, workflow, and documentation in this repository are licensed under the [MIT License](LICENSE). Mesa is a separate project: most Mesa code is MIT-licensed, while individual Mesa files and third-party components may use different licenses. The generated driver remains subject to the licenses included by the exact Mesa source revision used for the build and is not an official Mesa release artifact. See Mesa's [license and copyright documentation](https://docs.mesa3d.org/license.html).
