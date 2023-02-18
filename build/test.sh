
export ROOT=$(readlink -f $PWD)
export ROOT_DIR=$(readlink -f $(dirname $0)/..)

echo ${BUILD_CONFIG}
source "${ROOT_DIR}/build/config_setup.sh"

if [ "${HERMETIC_TOOLCHAIN:-0}" -eq 1 ]; then
echo "pass"
fi
#TODO: Continue with "OUT DIR"
