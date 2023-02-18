#
# This is the cross complie invocation, these variables will be export in build-kernel.sh
#

SRC_FOLDER=kernel_xiaomi_sm8350-miui
CLANG_PREBUILT_BIN=android-ndk-r25b-linux/toolchains/llvm/prebuilt/linux-x86_64/bin
LINUX_GCC_CROSS_COMPILE_PREBUILTS_BIN=gcc-android12L-release/aarch64-linux-android-4.9/
LINUX_GCC_CROSS_COMPILE_ARM32_PREBUILTS_BIN=gcc-android12L-release/arm-linux-androideabi-4.9/

CLANG_TRIPLE=aarch64-linux-gnu-
CROSS_COMPILE=aarch64-linux-gnu-
CROSS_COMPILE_ARM32=arm-linux-gnueabi-

DEFCONFIG=star_defconfig

ARCH=arm64
LLVM=1
CCACHE=1

FILES="
arch/arm64/boot/Image
"
AK3_COMPRESS=1

# Set for kernel zip
TARGET_OS=MIUI
DEVICE=STAR

#
# If you need overwrite some config but don't want to change defconfig, then use the function below to 
# overwrite the .config and complie with it.
#
#
# Usage: -e [config]: 				Enable the specified config
# 	 -d [config]: 				Disable the specified config
#	 -set-str [config] [value]: 		Overwrite the value of selected config

function overwrite_config() {
	scripts/config --file ${OUT_DIR}/.config \
		--set-str STATIC_USERMODEHELPER_PATH /system/bin/micd
}

# Use it to change the path or name of your extra script
PACTH_NAME=

PATCH_OUT_PRODUCT_HOOK=0
