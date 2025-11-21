FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies and MinGW cross-compiler
RUN apt-get update && apt-get install -y \
    git \
    wget \
    make \
    autoconf \
    automake \
    libtool \
    pkg-config \
    texinfo \
    mingw-w64 \
    libusb-1.0-0-dev \
    && rm -rf /var/lib/apt/lists/*

# 64-bit Windows target
ENV HOST=x86_64-w64-mingw32

WORKDIR /opt

# -----------------------------------------------------------------------------
# 1. Build libusb-1.0 for MinGW (Windows)
# -----------------------------------------------------------------------------
RUN wget https://github.com/libusb/libusb/releases/download/v1.0.26/libusb-1.0.26.tar.bz2 && \
    tar xf libusb-1.0.26.tar.bz2 && \
    rm libusb-1.0.26.tar.bz2

WORKDIR /opt/libusb-1.0.26

# Configure libusb for cross-compile to Windows
RUN ./configure \
    --host=${HOST} \
    --build=x86_64-pc-linux-gnu \
    --prefix=/usr/${HOST}

RUN make -j$(nproc) && make install

# Make sure pkg-config can see MinGW libusb
ENV PKG_CONFIG_PATH=/usr/${HOST}/lib/pkgconfig:${PKG_CONFIG_PATH}

# -----------------------------------------------------------------------------
# 2. Clone and prepare STM's OpenOCD fork
# -----------------------------------------------------------------------------
WORKDIR /opt

RUN git clone --depth 1 https://github.com/STMicroelectronics/OpenOCD.git openocd

WORKDIR /opt/openocd

# Generate autotools files manually (skip git2cl submodule)
RUN aclocal --warnings=all && \
    libtoolize --automake --copy && \
    autoconf --warnings=all && \
    autoheader --warnings=all && \
    automake --warnings=all --gnu --add-missing --copy

# Init only jimtcl submodule (required), skip git2cl & libjaylink
RUN git submodule update --init jimtcl

# -----------------------------------------------------------------------------
# 3. Configure STM OpenOCD for cross-build to Windows, ST-Link only
# -----------------------------------------------------------------------------
RUN ./configure \
    --host=${HOST} \
    --build=x86_64-pc-linux-gnu \
    --prefix=/opt/openocd-install \
    --disable-werror \
    --enable-stlink \
    --disable-ftdi \
    --disable-jlink \
    --disable-cmsis-dap \
    --disable-ti-icdi \
    --disable-ulink \
    --disable-usb-blaster-2 \
    --disable-rlink \
    --disable-kitprog \
    --disable-osbdm \
    --disable-buspirate

# -----------------------------------------------------------------------------
# 4. Build & install STM OpenOCD
# -----------------------------------------------------------------------------
RUN make -j$(nproc) && make install

# Default command: show built openocd version
CMD ["/opt/openocd-install/bin/openocd.exe", "--version"]