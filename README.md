***

# STM OpenOCD (Windows, STM32H5, ST‑Link) – Docker Cross Build

This project provides a **reproducible Docker-based build environment** to cross‑compile **STMicroelectronics’ OpenOCD fork** for **Windows (x86_64)**, with **ST‑Link** support and all standard OpenOCD scripts (`interface/`, `target/`, etc.).

The primary motivation is support for **STM32H5x** microcontrollers, which is not available in upstream OpenOCD.

## Overview

*   **Host:** Any machine that can run Docker (Linux, WSL2, etc.).
*   **Target:** **Windows** (`x86_64-w64-mingw32`) `openocd.exe`.
*   **JTAG/SWD interface:** **ST‑Link** (other probes disabled).
*   **Source:** [STMicroelectronics/OpenOCD](https://github.com/STMicroelectronics/OpenOCD).
*   **Build system:** **Docker + MinGW-w64 + autotools**.
*   **Extra:** Builds **libusb‑1.0** for MinGW so ST‑Link works properly on Windows.

**Resulting artifacts (to be used on Windows):**

*   `openocd.exe`
*   `share/openocd/` tree, including:
    *   `scripts/interface/`
    *   `scripts/target/`
    *   `scripts/board/`
    *   `contrib/`
*   Optionally `libusb-1.0.dll` if needed at runtime.

---

## Prerequisites

*   Docker installed and working.
*   Internet access for fetching:
    *   Ubuntu packages
    *   libusb source
    *   STM’s OpenOCD fork

You do **not** need MinGW, libusb, or autotools on your host – everything happens inside Docker.

---

## Dockerfile

The Dockerfile:
1.  Builds **libusb‑1.0.26** for the MinGW target.
2.  Builds **STM’s OpenOCD** for Windows.
3.  Installs OpenOCD to `/opt/openocd-install`.

```dockerfile
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
```

---

## Building the Docker Image

From the project root (where the Dockerfile lives):

```bash
docker build -t stm-openocd-mingw .
```

This will:
1.  Pull `ubuntu:22.04`.
2.  Install toolchain and build deps.
3.  Build libusb for MinGW.
4.  Clone STM’s OpenOCD fork.
5.  Build and install `openocd.exe` into `/opt/openocd-install`.

---

## Extracting Windows Artifacts

Create a container from the image and copy the installed files out:

```bash
CID=$(docker create stm-openocd-mingw)

# OpenOCD binary
docker cp "$CID":/opt/openocd-install/bin/openocd.exe ./openocd.exe

# OpenOCD scripts and contrib
docker cp "$CID":/opt/openocd-install/share/openocd ./openocd-share

# (Optional) libusb DLL for Windows, if present
docker cp "$CID":/usr/x86_64-w64-mingw32/bin/libusb-1.0.dll ./libusb-1.0.dll 2>/dev/null || true

docker rm "$CID"
```

After this you should have:
*   `./openocd.exe`
*   `./libusb-1.0.dll` (optional, only if built)
*   `./openocd-share/`
    *   `contrib/`
    *   `scripts/`
        *   `interface/`
        *   `target/`
        *   `board/`
        *   ...

---

## Installing on Windows

On your Windows machine, create a directory, e.g.:
`C:\tools\stm-openocd\`

Copy the files:
1.  `openocd.exe` → `C:\tools\stm-openocd\openocd.exe`
2.  `openocd-share` → `C:\tools\stm-openocd\share\openocd\`
3.  `libusb-1.0.dll` (if present/needed) → `C:\tools\stm-openocd\libusb-1.0.dll` (or next to `openocd.exe`)

**Final layout:**

```text
C:\tools\stm-openocd\
    openocd.exe
    libusb-1.0.dll          (if used)
    share\
        openocd\
            contrib\
            scripts\
                interface\
                target\
                board\
                ...
```

---

## Environment Setup on Windows

You can use either option below.

### Option A – Use `-s` to set scripts path

From `C:\tools\stm-openocd\`:

```cmd
openocd.exe ^
  -s share\openocd\scripts ^
  -f interface/stlink.cfg ^
  -f target/stm32h5x.cfg ^
  -c "bindto 0.0.0.0" ^
  -c "gdb_port 3333" ^
  -c "tcl_port 6666" ^
  -c "telnet_port 4444"
```

### Option B – Use `OPENOCD_SCRIPTS` env var (cleaner)

```cmd
set OPENOCD_SCRIPTS=C:\tools\stm-openocd\share\openocd\scripts

openocd.exe ^
  -f interface/stlink.cfg ^
  -f target/stm32h5x.cfg ^
  -c "bindto 0.0.0.0" ^
  -c "gdb_port 3333" ^
  -c "tcl_port 6666" ^
  -c "telnet_port 4444"
```

*   `interface/stlink.cfg` – ST‑Link interface.
*   `target/stm32h5x.cfg` – STM32H5 target (provided by STM fork).
*   Adjust the target file if you use a different STM32 family.

---

## Remote GDB Access

With OpenOCD running on the Windows host (listening on `0.0.0.0` and GDB port `3333`), from your dev machine:

```bash
arm-none-eabi-gdb your_firmware.elf
(gdb) target extended-remote <windows-host-ip>:3333
```

Telnet access for manual control:

```bash
telnet <windows-host-ip> 4444
```

Tcl port (if you automate via scripts):

```bash
nc <windows-host-ip> 6666
```

**Note:** Make sure Windows Firewall allows inbound connections on these ports.

---

## Example Minimal Board Config (Optional)

You can create a simple `h5.cfg` to simplify the command line. Example:

```tcl
# h5.cfg - STM32H5x + ST-Link

source [find interface/stlink.cfg]
transport select hla_swd

source [find target/stm32h5x.cfg]

reset_config srst_only srst_nogate connect_assert_srst

adapter_khz 4000
```

Place `h5.cfg` either:
1.  Next to `openocd.exe` and call with `-f h5.cfg` plus `-s`/`OPENOCD_SCRIPTS`.
2.  Inside `share\openocd\scripts\board\` and use `-f board/h5.cfg`.

**Example Usage:**

```cmd
set OPENOCD_SCRIPTS=C:\tools\stm-openocd\share\openocd\scripts

openocd.exe ^
  -f board/h5.cfg ^
  -c "bindto 0.0.0.0"
```

---

## Notes / Limitations

*   **Scope:** This setup is focused on ST‑Link + STM32H5x. Other probes (J-Link, CMSIS‑DAP, FTDI, etc.) are explicitly disabled to keep the build lean and the dependency chain simple.
*   **Adding Interfaces:** If you later need additional interfaces, you must:
    *   Install the appropriate MinGW libraries (libftdi, hidapi, etc.) inside Docker.
    *   Re-run `./configure` with more `--enable-*` flags.
*   **Assumptions:**
    *   You’re comfortable editing the Dockerfile if you want to tweak versions or enable more drivers.
    *   You manage Windows drivers for ST‑Link yourself (WinUSB vs ST’s driver, etc.).

---

## Troubleshooting

**`configure: error: libusb-1.x is required for the ST-Link Programmer`**
Means libusb wasn’t found (or the wrong one). This Dockerfile fixes that by:
1. Installing host `libusb-1.0-0-dev`.
2. Building MinGW libusb and exposing it via `PKG_CONFIG_PATH`.

**`cannot find -lusb-1.0 during link`**
Means MinGW libusb is missing or in the wrong place. This Dockerfile installs it to `/usr/x86_64-w64-mingw32` and sets `PKG_CONFIG_PATH` so OpenOCD’s configure sees it.

**OpenOCD on Windows complains about missing `libusb-1.0.dll`**
Copy `libusb-1.0.dll` from the container (see extraction step) next to `openocd.exe`.

---

## License

STM’s OpenOCD fork and libusb are under their respective open-source licenses.
This Docker-based build setup is just glue; follow STM/libusb license requirements for distribution and usage.