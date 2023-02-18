set -e

# Save environment for mixed build support.
OLD_ENVIRONMENT=$(mktemp)
export -p > ${OLD_ENVIRONMENT}

export ROOT=$(readlink -f $PWD)
export ROOT_DIR=$(readlink -f $(dirname $0)/..)

# Set current date
DATE=$(date +"%d.%m.%y")

# Save environment parameters before being overwritten by sourcing
# BUILD_CONFIG.
CC_ARG="${CC}"

source "${ROOT_DIR}/build/config_setup.sh"

MAKE_ARGS=( "$@" )
export MAKEFLAGS="-j$(nproc) ${MAKEFLAGS}"

cd ${ROOT_DIR}

export CLANG_TRIPLE CROSS_COMPILE CROSS_COMPILE_COMPAT CROSS_COMPILE_ARM32 ARCH MAKE_GOALS

# Restore the previously saved CC argument that might have been overridden by
# the BUILD_CONFIG.
[ -n "${CC_ARG}" ] && CC="${CC_ARG}"

# CC=gcc is effectively a fallback to the default gcc including any target
# triplets. An absolute path (e.g., CC=/usr/bin/gcc) must be specified to use a
# custom compiler.
[ "${CC}" == "gcc" ] && unset CC && unset CC_ARG

TOOL_ARGS=()

# LLVM=1 implies what is otherwise set below; it is a more concise way of
# specifying CC=clang LD=ld.lld NM=llvm-nm OBJCOPY=llvm-objcopy <etc>, for
# newer kernel versions.
if [[ -n "${LLVM}" ]]; then
  TOOL_ARGS+=("LLVM=1")
  # Reset a bunch of variables that the kernel's top level Makefile does, just
  # in case someone tries to use these binaries in this script such as in
  # initramfs generation below.
  if [[ -n "${CCACHE}" ]]; then
    echo "Use CCache"
    TOOL_ARGS+=("HOSTCC=ccache clang")
    TOOL_ARGS+=("HOSTCXX=ccache clang++")
    TOOL_ARGS+=("CC=ccache clang")
  else
    HOSTCC=clang
    HOSTCXX=clang++
    CC=clang
  fi
  LD=ld.lld
  AR=llvm-ar
  NM=llvm-nm
  OBJCOPY=llvm-objcopy
  OBJDUMP=llvm-objdump
  READELF=llvm-readelf
  OBJSIZE=llvm-size
  STRIP=llvm-strip
else
  if [[ -n "${CCACHE}" ]]; then
    if [ -n "${HOSTCC}" ]; then
      TOOL_ARGS+=("HOSTCC=ccache ${HOSTCC}")
    fi

    if [ -n "${CC}" ]; then
      TOOL_ARGS+=("CC=ccache ${CC}")
      if [ -z "${HOSTCC}" ]; then
        TOOL_ARGS+=("HOSTCC=ccache ${CC}")
      fi
    fi
  else
    if [ -n "${HOSTCC}" ]; then
      TOOL_ARGS+=("HOSTCC=${HOSTCC}")
    fi

    if [ -n "${CC}" ]; then
      TOOL_ARGS+=("CC=${CC}")
      if [ -z "${HOSTCC}" ]; then
        TOOL_ARGS+=("HOSTCC=${CC}")
      fi
    fi
  fi

  if [ -n "${LD}" ]; then
    TOOL_ARGS+=("LD=${LD}" "HOSTLD=${LD}")
  fi

  if [ -n "${NM}" ]; then
    TOOL_ARGS+=("NM=${NM}")
  fi

  if [ -n "${OBJCOPY}" ]; then
    TOOL_ARGS+=("OBJCOPY=${OBJCOPY}")
  fi
fi

if [ -n "${LLVM_IAS}" ]; then
  TOOL_ARGS+=("LLVM_IAS=${LLVM_IAS}")
  # Reset $AS for the same reason that we reset $CC etc above.
  AS=clang
fi

if [ -n "${DEPMOD}" ]; then
  TOOL_ARGS+=("DEPMOD=${DEPMOD}")
fi

if [ -n "${DTC}" ]; then
  TOOL_ARGS+=("DTC=${DTC}")
fi

# Allow hooks that refer to $CC_LD_ARG to keep working until they can be
# updated.
CC_LD_ARG="${TOOL_ARGS[@]}"

mkdir -p ${OUT_DIR} ${DIST_DIR}

echo "========================================================"
echo " Setting up for build"
if [ "${SKIP_MRPROPER}" != "1" ] ; then
  set -x
  (cd ${KERNEL_DIR} && make "${TOOL_ARGS[@]}" O=${OUT_DIR} "${MAKE_ARGS[@]}" mrproper)
  set +x
fi

if [ "${SKIP_DEFCONFIG}" != "1" ] ; then
  set -x
  (cd ${KERNEL_DIR} && make "${TOOL_ARGS[@]}" O=${OUT_DIR} "${MAKE_ARGS[@]}" ${DEFCONFIG})
  set +x

  if [ -n "${POST_DEFCONFIG_CMDS}" ]; then
    echo "========================================================"
    echo " Running pre-make command(s):"
    set -x
    eval ${POST_DEFCONFIG_CMDS}
    set +x
  fi
fi

if [ "${LTO}" = "none" -o "${LTO}" = "thin" -o "${LTO}" = "full" ]; then
  echo "========================================================"
  echo " Modifying LTO mode to '${LTO}'"

  set -x
  if [ "${LTO}" = "none" ]; then
    ${KERNEL_DIR}/scripts/config --file ${OUT_DIR}/.config \
      -d LTO_CLANG \
      -e LTO_NONE \
      -d LTO_CLANG_THIN \
      -d LTO_CLANG_FULL \
      -d THINLTO
  elif [ "${LTO}" = "thin" ]; then
    # This is best-effort; some kernels don't support LTO_THIN mode
    # THINLTO was the old name for LTO_THIN, and it was 'default y'
    ${KERNEL_DIR}/scripts/config --file ${OUT_DIR}/.config \
      -e LTO_CLANG \
      -d LTO_NONE \
      -e LTO_CLANG_THIN \
      -d LTO_CLANG_FULL \
      -e THINLTO
  elif [ "${LTO}" = "full" ]; then
    # THINLTO was the old name for LTO_THIN, and it was 'default y'
    ${KERNEL_DIR}/scripts/config --file ${OUT_DIR}/.config \
      -e LTO_CLANG \
      -d LTO_NONE \
      -d LTO_CLANG_THIN \
      -e LTO_CLANG_FULL \
      -d THINLTO
  fi
  (cd ${OUT_DIR} && make "${TOOL_ARGS[@]}" O=${OUT_DIR} "${MAKE_ARGS[@]}" olddefconfig)
  set +x
elif [ -n "${LTO}" ]; then
  echo "LTO= must be one of 'none', 'thin' or 'full'."
  exit 1
fi

echo "========================================================"
echo " Building kernel"

set -x
(cd ${OUT_DIR} && make O=${OUT_DIR} "${TOOL_ARGS[@]}" "${MAKE_ARGS[@]}" ${MAKE_GOALS})
set +x

echo "========================================================"
echo " Copying files"
for FILE in $(cd ${OUT_DIR} && ls -1 ${FILES}); do
  if [ -f ${OUT_DIR}/${FILE} ]; then
    echo "  $FILE"
    if [ -n ${AK3_COMPRESS} ]; then
      filename=$(basename ${FILE})
      ZIPNAME="Voyager-${DEVICE}-build${BUILD}-${TARGET_OS}-${DATE}.zip"
      mkdir -p ${DIST_DIR}/tmp
      cp -r ${ROOT}/tools/anykernel/* ${DIST_DIR}/tmp
      mkdir -p ${DIST_DIR}/tmp/kernels/${TARGET_OS,,}
      cp ${OUT_DIR}/${FILE} ${DIST_DIR}/tmp/kernels/${TARGET_OS,,}
      echo ${filename} > ${DIST_DIR}/tmp/files
      cd ${DIST_DIR}/tmp && zip -r9 ${DIST_DIR}/${ZIPNAME} ./* -x .git .gitignore out/ ./*.zip && rm -r ${DIST_DIR}/tmp
      echo " Files compressed to ${DIST_DIR}"
    fi
    cp -p ${OUT_DIR}/${FILE} ${DIST_DIR}/
  else
    echo "  $FILE is not a file, skipping"
  fi
done

NEW_COUNT=$((BUILD + 1))
echo " Next version is $NEW_COUNT"
echo "BUILD_COUNT=${NEW_COUNT}" > "${ROOT_DIR}/build_status"

echo "========================================================"
echo " Files copied to ${DIST_DIR}"
