
[ -n "$_SETUP_ENV_SH_INCLUDED" ] && return || _SETUP_ENV_SH_INCLUDED=1

export BUILD_CONFIG=${BUILD_CONFIG:-build.config}

export KERNEL_DIR
# for case that KERNEL_DIR is not specified in environment
if [ -z "${KERNEL_DIR}" ]; then
    # for the case that KERNEL_DIR is not specified in the BUILD_CONFIG file
    # use the directory of the build config file as KERNEL_DIR
    # for the case that KERNEL_DIR is specified in the BUILD_CONFIG file,
    # or via the config files sourced, the value of KERNEL_DIR
    # set here would be overwritten, and the specified value would be used.
    build_config_path=$(realpath ${ROOT}/${BUILD_CONFIG})
    build_config_dir=$(dirname ${build_config_path})
    . ${ROOT}/${BUILD_CONFIG}
    export SRC_FOLDER
    build_config_dir=${build_config_dir##${ROOT}/}
    KERNEL_DIR="${SRC_FOLDER}"
    echo "= Set default KERNEL_DIR: ${SRC_FOLDER}"
else
    echo "= User environment KERNEL_DIR: ${KERNEL_DIR}"
fi

if [ ! -f ${ROOT_DIR}/build_status ]; then
    echo "Initializing.."
    BUILD=1
    echo "BUILD_COUNT=${BUILD}" > "${ROOT_DIR}/build_status"
fi

GET_BUILD_COUNT=$(awk -F "=" '/BUILD_COUNT/ {print $2}' "${ROOT_DIR}/build_status")
BUILD=$GET_BUILD_COUNT

cat /dev/null > "${ROOT_DIR}/build_status"                      #clean all info
{								#Always Print them
  echo "BUILD_COUNT=${BUILD}"
  echo "DEVICE=${DEVICE}"
  echo "TARGET_OS=${TARGET_OS}"
} >> "${ROOT_DIR}/build_status"

export COMMON_OUT_DIR=$(readlink -m ${OUT_DIR:-${ROOT_DIR}/out${OUT_DIR_SUFFIX}/${BRANCH}})
export OUT_DIR=$(readlink -m ${COMMON_OUT_DIR}/${KERNEL_DIR})
export DIST_DIR=$(readlink -m ${DIST_DIR:-${COMMON_OUT_DIR}/dist})

PREBUILTS_PATHS=(
LINUX_GCC_CROSS_COMPILE_PREBUILTS_BIN
LINUX_GCC_CROSS_COMPILE_ARM32_PREBUILTS_BIN
LINUX_GCC_CROSS_COMPILE_COMPAT_PREBUILTS_BIN
CLANG_PREBUILT_BIN
)

for PREBUILT_BIN in "${PREBUILTS_PATHS[@]}"; do
	PREBUILT_BIN=\${${PREBUILT_BIN}}
	eval PREBUILT_BIN="${PREBUILT_BIN}"
	if [ -n "${PREBUILT_BIN}" ]; then
		# Mitigate dup paths
		CC_PATH=${ROOT}/tools/${PREBUILTS_PATHS[4]}/
		PATH=${PATH//"${ROOT}/tools/toolchains\/${PREBUILT_BIN}:"}
		PATH=${ROOT}/tools/toolchains/${PREBUILT_BIN}:${PATH}
	fi
done

export PATH

echo "================================================================="

cat "$build_config_path"

echo ""
echo "================================================================="
echo ""

echo "PATH=${PATH}"

echo "ARCH=${ARCH}"
echo "FILE=${FILES}"
echo "DEFCONFIG=${DEFCONFIG}"
echo "COMMON_OUT_DIR=${COMMON_OUT_DIR}"
echo "OUT_DIR=${OUT_DIR}"
echo "DIST_DIR=${DIST_DIR}"
echo "================================================================="

# verifies that defconfig matches the DEFCONFIG
function check_defconfig() {
    (cd ${OUT_DIR} && \
     make "${TOOL_ARGS[@]}" O=${OUT_DIR} savedefconfig)
    [ "$ARCH" = "x86_64" -o "$ARCH" = "i386" ] && local ARCH=x86
    echo Verifying that savedefconfig matches ${KERNEL_DIR}/arch/${ARCH}/configs/${DEFCONFIG}
    RES=0
    diff -u ${KERNEL_DIR}/arch/${ARCH}/configs/${DEFCONFIG} ${OUT_DIR}/defconfig >&2 ||
      RES=$?
    if [ ${RES} -ne 0 ]; then
        echo ERROR: savedefconfig does not match ${KERNEL_DIR}/arch/${ARCH}/configs/${DEFCONFIG} >&2
    fi
    return ${RES}
}
export -f check_defconfig
