# Mesa Turnip Android Builder

GitHub Actions project for building the latest official stable Mesa Turnip Vulkan driver for Android ARM64 devices using the KGSL backend.

The build selects the newest final `mesa-X.Y.Z` tag from upstream Mesa at runtime. Release candidates, beta tags, development branches, and external patch sets are excluded.

## Output

Each successful workflow produces:

```text
Mesa-Turnip-AdrenoTools.<mesa-version>.zip
Mesa-Turnip-Magisk.<mesa-version>.zip
SHA256SUMS.txt
SHA512SUMS.txt
```

The driver ZIP is an AdrenoTools-compatible flat package containing:

```text
libvulkan_freedreno.so
meta.json
```

Both packages are produced from the same compiled Turnip library. No package
installs anything on a device automatically.

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

1. Builds the pinned Docker image.
2. Uses the tagged Mesa release for release builds and the workflow's pinned Mesa baseline for other builds.
3. Cross-compiles Turnip with Android NDK r29.
4. Validates that the result is an AArch64 ELF shared library.
5. Creates and validates both the AdrenoTools ZIP and Magisk module ZIP from the same binary.
6. Uploads both package ZIPs and combined SHA-256/SHA-512 checksum files as one artifact.

The Magisk package contains the same compiled driver under
`system/vendor/lib64/hw/`. Its SONAME and filename are changed to the
device-specific Vulkan HAL name; the workflow default is `vulkan.adreno.so`,
and local builds can override it with `MAGISK_VULKAN_FILENAME`.

The Magisk package is an experimental global Vulkan override. It can also
replace the driver used by Android HWUI and system services, so it is not the
recommended way to test Turnip with individual games. Prefer the AdrenoTools
package with per-app driver selection. Keep the stock or device vendor driver
enabled globally, and do not enable multiple modules that overlay the same
`vulkan*.so` path.

## Local build

Docker is required. From the repository root:

```bash
mkdir -p out
docker build --platform linux/amd64 -t mesa-turnip-builder .
docker run --rm \
  --platform linux/amd64 \
  -e MAGISK_VULKAN_FILENAME=vulkan.adreno.so \
  -v "$PWD/out:/out" \
  mesa-turnip-builder
```

The local build downloads the newest stable Mesa release during the container run unless
`MESA_TAG` is supplied. CI pins its non-release baseline explicitly. The selected tag
and commit are stored in `meta.json`.

To reproduce a specific final release:

```bash
docker run --rm \
  --platform linux/amd64 \
  -e MESA_TAG=mesa-26.2.0 \
  -e PACKAGE_NAME=Mesa-Turnip-AdrenoTools \
  -e MAGISK_VULKAN_FILENAME=vulkan.adreno.so \
  -v "$PWD/out:/out" \
  mesa-turnip-builder
```

The single build writes both package ZIPs and combined
`SHA256SUMS.txt`/`SHA512SUMS.txt` files into `out/`.
Package names use the format `<package>.<mesa-version>.zip`.

### Creating a GitHub release

Push a tag matching the upstream Mesa release tag to build that exact Mesa
version and publish a GitHub release:

```bash
git tag -s mesa-26.2.0 -m "release Mesa Turnip mesa-26.2.0"
git push origin mesa-26.2.0
```

The release contains both the AdrenoTools and Magisk ZIPs, plus combined
`SHA256SUMS.txt` and `SHA512SUMS.txt` files. Normal pushes to `main` build and
upload workflow artifacts without creating a release.

The weekly `Propose Mesa update` workflow checks upstream stable tags, extracts
only `tu:`, `tu/<subsystem>:`, and `vulkan/android:` release-note entries, and opens one update PR
when the pinned CI baseline changes. The PR must be reviewed and merged by a
maintainer before a release is created. The same filtered notes are used as the
GitHub release description. The workflow also queues the PR for squash
auto-merge; GitHub waits for required checks and reviews before merging.

When that automated baseline PR merges, `Publish automatic Mesa baseline
release` creates the matching `mesa-X.Y.Z` tag. The existing release workflow
is explicitly dispatched on that tag and builds and publishes the driver pack
with the filtered Turnip notes.
Manual changes to `main` do not create releases.

The optional `Android Vulkan smoke test` workflow runs on a self-hosted runner
labelled `android-device`. It records the device GPU properties, launches the
requested package, verifies that it remains foreground, and uploads logcat
evidence only when the test fails. The evidence is filtered and retained for
one day. It does not install or switch driver modules.

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
untested driver on a production device. On devices with a known-compatible
vendor or OEM Adreno package, use that package for system-wide rendering and
select Turnip only per app.

### Per-app testing policy

For Android apps that use `AHardwareBuffer` or are rendered through Android
HWUI, validate Turnip through an AdrenoTools-compatible per-app selector first.
If an app crashes with an `Invalid GrBackendFormat` or similar RenderThread
abort, disable the global Magisk override and reproduce with the stock driver.
That indicates a Turnip Android WSI/AHardwareBuffer compatibility issue, not a
filename mismatch. Do not work around it by enabling a second Adreno module;
multiple overlays of `vulkan.adreno.so` are unsupported.

## Scope and licensing

The builder scripts, Dockerfile, workflow, and documentation in this repository are licensed under the [MIT License](LICENSE). Mesa is a separate project: most Mesa code is MIT-licensed, while individual Mesa files and third-party components may use different licenses. The generated driver remains subject to the licenses included by the exact Mesa source revision used for the build and is not an official Mesa release artifact. See Mesa's [license and copyright documentation](https://docs.mesa3d.org/license.html).
