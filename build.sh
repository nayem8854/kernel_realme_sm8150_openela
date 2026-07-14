#!/bin/bash

set -e

KERNEL_DIR="$(pwd)"
OUT_DIR="$KERNEL_DIR/out"

TC_DIR="$KERNEL_DIR/toolchains"
CLANG_DIR="$TC_DIR/clang-r547379"

ANYKERNEL_DIR="$KERNEL_DIR/AnyKernel3"

CONFIG_FILE="samurai_defconfig"

KERNEL_NAME="Hyper-RMX1931"
ZIP_NAME="${KERNEL_NAME}-$(date +"%d%m%Y-%H%M")-KSU.zip"

export ARCH=arm64
export SUBARCH=arm64

export KBUILD_BUILD_USER=build-user
export KBUILD_BUILD_HOST=nayem8854
export KBUILD_BUILD_VERSION=1

GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

install_deps() {

    echo -e "${GREEN}Installing dependencies...${NC}"

    apt-get update

    apt-get install -y \
        bc \
		python2 \
        git-core \
        gnupg \
        flex \
        bison \
        build-essential \
        zip \
        curl \
        wget \
        zlib1g-dev \
        libc6-dev-i386 \
        libncurses5 \
        lib32ncurses5-dev \
        x11proto-core-dev \
        libx11-dev \
        lib32z1-dev \
        libgl1-mesa-dev \
        libxml2-utils \
        xsltproc \
        unzip \
        fontconfig \
        libssl-dev \
        ccache \
        cpio || true
}

download_clang() {

    if [ -d "$CLANG_DIR/bin" ]; then
        echo -e "${GREEN}Clang already exists${NC}"
        return
    fi

    echo -e "${GREEN}Downloading Android LLVM Clang...${NC}"

    mkdir -p "$TC_DIR"

    git clone --depth=1 \
        https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r547379.git \
        "$CLANG_DIR"
}

setup_env() {

    export PATH="$CLANG_DIR/bin:$PATH"

    if command -v ccache >/dev/null 2>&1; then
        export CC="ccache clang"
    else
        export CC="clang"
    fi
}

clean() {
    rm -rf "$OUT_DIR"
}

install_ksu() {

    if [[ "$1" == "ksu" ]]; then

        echo -e "${GREEN}Installing KernelSU-Next...${NC}"

        curl -LSs \
        "https://github.com/KernelSU-Next/KernelSU-Next/raw/13ad2b4cbdad7b14324a4f7867110bb86a8dc411/kernel/setup.sh" \
        | bash -s legacy

        DEFCONFIG_FILE="arch/arm64/configs/${CONFIG_FILE}"

        echo -e "${GREEN}Patching ${DEFCONFIG_FILE}${NC}"

        grep -qxF "CONFIG_KPROBES=y" "$DEFCONFIG_FILE" || \
        echo "CONFIG_KPROBES=y" >> "$DEFCONFIG_FILE"

        grep -qxF "CONFIG_KPROBE_EVENTS=y" "$DEFCONFIG_FILE" || \
        echo "CONFIG_KPROBE_EVENTS=y" >> "$DEFCONFIG_FILE"

        grep -qxF "CONFIG_KSU_KPROBE_HOOKS=y" "$DEFCONFIG_FILE" || \
        echo "CONFIG_KSU_KPROBE_HOOKS=y" >> "$DEFCONFIG_FILE"

        grep -qxF "CONFIG_KSU=y" "$DEFCONFIG_FILE" || \
        echo "CONFIG_KSU=y" >> "$DEFCONFIG_FILE"

        echo -e "${GREEN}KernelSU config added${NC}"
        echo -e "${GREEN}KernelSU-Next installed${NC}"
    fi
}

make_defconfig() {

    echo -e "${GREEN}Generating ${CONFIG_FILE}${NC}"

    make O="$OUT_DIR" \
         ARCH=arm64 \
         "$CONFIG_FILE"
}

compile_kernel() {

    echo -e "${GREEN}Building kernel...${NC}"

    make -j"$(nproc --all)" \
        O="$OUT_DIR" \
        ARCH=arm64 \
        CC="$CC" \
        LLVM=1 \
        LLVM_IAS=1 \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        2>&1 | tee build.log
}

completion() {

    COMPILED_IMAGE=""

    if [[ -f "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" ]]; then
        COMPILED_IMAGE="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"
    elif [[ -f "$OUT_DIR/arch/arm64/boot/Image.gz" ]]; then
        COMPILED_IMAGE="$OUT_DIR/arch/arm64/boot/Image.gz"
    fi

    COMPILED_DTBO="$OUT_DIR/arch/arm64/boot/dtbo.img"

    if [[ -n "$COMPILED_IMAGE" ]]; then

        echo -e "${GREEN}Packaging AnyKernel3...${NC}"

        rm -rf "$ANYKERNEL_DIR"

        git clone --depth=1 \
            -b rmx1931 \
            https://github.com/nayem8854/AnyKernel3.git \
            "$ANYKERNEL_DIR"

        cp -f "$COMPILED_IMAGE" "$ANYKERNEL_DIR/"

        if [[ -f "$COMPILED_DTBO" ]]; then
            cp -f "$COMPILED_DTBO" "$ANYKERNEL_DIR/"
        fi

        cd "$ANYKERNEL_DIR"

        find . -name "*.zip" -type f -delete

        zip -r9 AnyKernel.zip ./*

        mv AnyKernel.zip "$ZIP_NAME"
        mv "$ZIP_NAME" "$KERNEL_DIR/"

        cd "$KERNEL_DIR"

        rm -rf "$ANYKERNEL_DIR"

        END=$(date +%s)
        DIFF=$((END - START))

        echo
        echo "Build Time: ${DIFF} seconds"
        echo

        echo

        echo -e "${GREEN}############################################${NC}"
        echo -e "${GREEN}############# OkThisIsEpic! ################${NC}"
        echo -e "${GREEN}############################################${NC}"

        echo
        echo "Output:"
        echo "$KERNEL_DIR/$ZIP_NAME"

        exit 0

    else

        echo -e "${RED}############################################${NC}"
        echo -e "${RED}##         This Is Not Epic :'(          ##${NC}"
        echo -e "${RED}############################################${NC}"

        echo
        echo "Missing: Image.gz-dtb or Image.gz"

        exit 1
    fi
}

START=$(date +%s)

#install_deps
download_clang
setup_env
install_ksu "$1"
#clean
make_defconfig
compile_kernel
completion
