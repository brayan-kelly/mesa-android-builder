# SPDX-License-Identifier: MIT
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    ANDROID_NDK_HOME=/opt/android-ndk-r29 \
    API_LEVEL=34 \
    PATH=/opt/android-ndk-r29/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
    bison \
    build-essential \
    ca-certificates \
    clang \
    curl \
    file \
    flex \
    git \
    libdrm-dev \
    libelf-dev \
    libexpat1-dev \
    lld \
    meson \
    ninja-build \
    pkg-config \
    python3 \
    python3-mako \
    python3-packaging \
    python3-ply \
    unzip \
    wget \
    zip \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

RUN curl -fsSL \
      https://dl.google.com/android/repository/android-ndk-r29-linux.zip \
      -o /tmp/android-ndk.zip \
    && unzip -q /tmp/android-ndk.zip -d /opt \
    && rm -f /tmp/android-ndk.zip

COPY build.sh /opt/build.sh
RUN chmod 0755 /opt/build.sh

ENTRYPOINT ["/opt/build.sh"]
