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

# KernelSU-Next kprobes mode omits ksu_input_hook, but selinux_hide.c
# still references it on kernels >= 4.10 (linker: undefined symbol).
# Always define the flag and clear it when the input hook stops.
patch_ksu_input_hook() {
    local f=""
    for candidate in \
        "KernelSU-Next/kernel/runtime/ksud_integration.c" \
        "drivers/kernelsu/runtime/ksud_integration.c" \
        "KernelSU-Next/kernel/ksud.c" \
        "drivers/kernelsu/ksud.c"
    do
        if [[ -f "$candidate" ]]; then
            f="$candidate"
            break
        fi
    done

    if [[ -z "$f" ]]; then
        echo -e "${RED}KernelSU source not found; skip ksu_input_hook patch${NC}"
        return 0
    fi

    if ! grep -q "bool ksu_input_hook" "$f"; then
        echo -e "${RED}ksu_input_hook not present in $f; skip patch${NC}"
        return 0
    fi

    # Already patched?
    if grep -q "ksu_input_hook always defined for selinux_hide" "$f"; then
        echo -e "${GREEN}ksu_input_hook patch already applied${NC}"
        return 0
    fi

    python3 - "$f" <<'PY'
import re, sys
path = sys.argv[1]
src = open(path, encoding="utf-8", errors="replace").read()
orig = src
marker = "/* ksu_input_hook always defined for selinux_hide */"

def_re = re.compile(
    r"^[ \t]*bool\s+ksu_input_hook\s+__read_mostly\s*=\s*true\s*;[ \t]*\n",
    re.M,
)

def is_inside_else_of_kprobes(text, pos):
    """True if pos sits in the #else branch of #ifdef KSU_KPROBES_HOOK."""
    # Walk backward to nearest #ifdef KSU_KPROBES_HOOK / #else / #endif
    before = text[:pos]
    # Find last relevant preprocessor directive before pos
    dirs = list(re.finditer(
        r"^[ \t]*#(ifdef\s+KSU_KPROBES_HOOK|ifndef\s+KSU_KPROBES_HOOK|else|endif)\b",
        before,
        flags=re.M,
    ))
    if not dirs:
        return False
    last = dirs[-1]
    kind = last.group(1)
    if kind.startswith("else"):
        # Confirm the matching open is KSU_KPROBES_HOOK
        for d in reversed(dirs[:-1]):
            k = d.group(1)
            if k.startswith("endif"):
                break
            if "KSU_KPROBES_HOOK" in k:
                return k.startswith("ifdef")  # #else of #ifdef KSU_KPROBES_HOOK
            break
    return False

# 1) Ensure a file-scope definition is NOT only under #else of KPROBES_HOOK.
if marker not in src:
    matches = list(def_re.finditer(src))
    need_hoist = False
    if not matches:
        need_hoist = True
    else:
        # If every definition is inside the kprobes #else, hoist one out.
        need_hoist = all(is_inside_else_of_kprobes(src, m.start()) for m in matches)

    if need_hoist:
        # Drop only definitions that live under the kprobes #else branch.
        parts = []
        last = 0
        for m in matches:
            if is_inside_else_of_kprobes(src, m.start()):
                parts.append(src[last:m.start()])
                last = m.end()
        parts.append(src[last:])
        src = "".join(parts) if matches else src

        # Insert after the include block (and any mid-include ifdefs).
        includes = list(re.finditer(r"^#include[^\n]*\n", src, flags=re.M))
        insert_at = includes[-1].end() if includes else 0
        # Skip trailing #endif that closes an include guard ifdef.
        tail = src[insert_at:insert_at + 200]
        m_end = re.match(r"(?:\s*#endif[^\n]*\n)+", tail)
        if m_end:
            insert_at += m_end.end()
        decl = f"\n{marker}\nbool ksu_input_hook __read_mostly = true;\n\n"
        src = src[:insert_at] + decl + src[insert_at:]
    # else: already has an unconditional definition (older ksud.c) — leave it

# 2) Clear the flag in stop_input_hook() for the kprobes path so
#    selinux_hide's wait loop can exit. Manual-hook (#else) already
#    clears it; kprobes branch only unregisters the probe.
def patch_stop_input(text):
    m = re.search(
        r"((?:static\s+)?void\s+stop_input_hook\s*\(\s*\)\s*\{)(.*?)(\n\})",
        text,
        flags=re.S,
    )
    if not m:
        return text
    body = m.group(2)
    kprobes_ifdef = r"#ifdef\s+(?:CONFIG_)?KSU_KPROBES_HOOK\s*\n"
    # Already cleared right after local decls in the kprobes branch?
    if re.search(
        kprobes_ifdef
        + r"(?:[ \t]*static[^\n]*\n)*"
        + r"[ \t]*ksu_input_hook\s*=\s*false\s*;",
        body,
    ):
        return text
    # Place after local decls to avoid -Werror=declaration-after-statement
    body2, n = re.subn(
        r"(" + kprobes_ifdef + r"(?:[ \t]*static[^\n]*\n)*)",
        r"\1\tksu_input_hook = false;\n",
        body,
        count=1,
    )
    if n == 0:
        # No kprobes branch — only patch if flag is never cleared
        if "ksu_input_hook = false" in body:
            return text
        body2 = "\n\tksu_input_hook = false;" + body
    return text[: m.start()] + m.group(1) + body2 + m.group(3) + text[m.end() :]

src = patch_stop_input(src)

if src == orig:
    print(f"no changes needed for {path}")
else:
    open(path, "w", encoding="utf-8").write(src)
    print(f"patched {path}")
PY
}

install_ksu() {

    if [[ "$1" == "ksu" ]]; then

        echo -e "${GREEN}Installing KernelSU-Next...${NC}"

        curl -LSs \
        "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" \
        | bash -s legacy

        patch_ksu_input_hook

        DEFCONFIG_FILE="arch/arm64/configs/${CONFIG_FILE}"

        echo -e "${GREEN}Patching ${DEFCONFIG_FILE}${NC}"

        # Remove obsolete/wrong option name from older builds
        sed -i '/^CONFIG_KSU_KPROBE_HOOKS=/d' "$DEFCONFIG_FILE" 2>/dev/null || true

        grep -qxF "CONFIG_KPROBES=y" "$DEFCONFIG_FILE" || \
        echo "CONFIG_KPROBES=y" >> "$DEFCONFIG_FILE"

        grep -qxF "CONFIG_KRETPROBES=y" "$DEFCONFIG_FILE" || \
        echo "CONFIG_KRETPROBES=y" >> "$DEFCONFIG_FILE"

        grep -qxF "CONFIG_KPROBE_EVENTS=y" "$DEFCONFIG_FILE" || \
        echo "CONFIG_KPROBE_EVENTS=y" >> "$DEFCONFIG_FILE"

        # Correct Kconfig symbol is CONFIG_KSU_KPROBES_HOOK (not KPROBE_HOOKS)
        grep -qxF "CONFIG_KSU_KPROBES_HOOK=y" "$DEFCONFIG_FILE" || \
        echo "CONFIG_KSU_KPROBES_HOOK=y" >> "$DEFCONFIG_FILE"

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