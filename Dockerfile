# SPDX-License-Identifier: MIT
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    ANDROID_NDK_HOME=/opt/android-ndk-r29 \
    API_LEVEL=34 \
    PATH=/opt/venv/bin:/opt/android-ndk-r29/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
    bison \
    build-essential \
    ca-certificates \
    clang \
    curl \
    file \
    flex \
    git \
    glslang-tools \
    libdrm-dev \
    libelf-dev \
    libexpat1-dev \
    lld \
    meson \
    ninja-build \
    patchelf \
    pkg-config \
    python3 \
    python3-mako \
    python3-packaging \
    python3-ply \
    python3-pip \
    python3-venv \
    unzip \
    wget \
    zip \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv --system-site-packages /opt/venv \
    && /opt/venv/bin/python -m pip install --no-cache-dir \
        'meson>=1.4.0,<2' \
        'PyYAML==6.0.2' \
    && /opt/venv/bin/python -c 'import yaml; print("PyYAML", yaml.__version__)' \
    && /opt/venv/bin/meson --version

WORKDIR /opt

RUN curl -fsSL \
      https://dl.google.com/android/repository/android-ndk-r29-linux.zip \
      -o /tmp/android-ndk.zip \
    && unzip -q /tmp/android-ndk.zip -d /opt \
    && rm -f /tmp/android-ndk.zip

COPY build.sh /opt/build.sh
COPY mesa-build-common.sh /opt/mesa-build-common.sh
COPY build-turnip-magisk.sh /opt/build-turnip-magisk.sh
COPY build-freeadreno-magisk.sh /opt/build-freeadreno-magisk.sh
RUN chmod 0755 /opt/build.sh /opt/mesa-build-common.sh \
    /opt/build-turnip-magisk.sh /opt/build-freeadreno-magisk.sh

ENTRYPOINT ["/opt/build.sh"]
