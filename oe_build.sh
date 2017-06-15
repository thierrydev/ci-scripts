#!/bin/bash

#make sure current dir is same as location of script
cd "$(dirname "$0")"

# print all env variables from mesos or local environment
env

source common.sh

TOP=/home/wrlbuild
BRANCH=WRLINUX_9_BASE
BUILD_NAME=generic
HOST=
EMAIL=
SETUP_ARGS=()
PREBUILD_CMD=()
BUILD_CMD=()
WORLD_BUILD=
SKIP_CLEANUP=no
WRLINUX=
ARCH=$(uname -m)

echo "Command: $0"
for i in "$@"
do
    echo "Arg: $i"
    case $i in
        --top=*)                TOP=${i#*=} ;;
        --branch=*)             BRANCH=${i#*=} ;;
        --host=*)               HOST=${i#*=} ;;
        --setup_args=*)         SETUP_ARGS=(${i#*=}) ;;
        --name=*)               BUILD_NAME=${i#*=} ;;
        --email=*)              EMAIL=${i#*=} ;;
        --prebuild_cmd=*)       PREBUILD_CMD=(${i#*=}) ;;
        --build_id=*)           BUILD_ID=${i#*=} ;;
        --build_cmd=*)          BUILD_CMD=(${i#*=}) ;;
        --post-success=*)       POST_SUCCESS=${i#*=} ;;
        --post-fail=*)          POST_FAIL=${i#*=} ;;
        --world_build=*)        WORLD_BUILD=${i#*=} ;;
        --skip-cleanup=*)       SKIP_CLEANUP=${i#*=} ;;
        --wrlinux=*)            WRLINUX=${i#*=} ;;
        --fail_repo=*)          FAIL_REPO=${i#*=} ;; # override default in configs.sh
        *)                      ;;
    esac
    shift
done

HOME="$TOP"
if [ -z "$WRLINUX" ]; then
    WRLINUX="$TOP/wrlinux-$BRANCH/wrlinux-9"
fi

BUILD=
create_build_dir
cd "$BUILD"

TIME="/usr/bin/time $QUIET -f %e -o $BUILD/time.log"

STATFILE=$BUILD/buildstats.log
create_statfile "$STATFILE"

# Make a clone of local mirror so setup will use local mirror
wrlinux_setup_clone "$WRLINUX" "$BUILD" "$BRANCH" "$TOP"

# Start the hang check by the build post process script
touch "$BUILD/00-INPROGRESS"

# run the setup tool
SETUP_ARGS=("${SETUP_ARGS[@]}")
log "setup.sh ${SETUP_ARGS[*]}" 2>&1 | tee "$BUILD/00-wrsetup.log"
$TIME "$BUILD/${WRLINUX:(-9)}/setup.sh" "${SETUP_ARGS[@]}" >> "$BUILD/00-wrsetup.log" 2>&1
RET=$?
log_stats "Setup" "$BUILD"
echo "Setup: ${SETUP_ARGS[*]}" >> "$STATFILE"

if [ "$RET" != 0 ]; then
    log "Setup failed"
    echo "FinishUTC: $(date +%s)" >> "$STATFILE"
    echo "Status: FAILED" >> "$STATFILE"
else
    # Use the buildtools, setup env, run prebuild script and do build
    . ./environment-setup-x86_64-wrlinuxsdk-linux
    . ./oe-init-build-env "$BUILD_NAME" > "$BUILD/00-prebuild.log" 2>&1

    # Run prebuild command which may modify files like local.conf
    log "$TOP/ci-scripts/${PREBUILD_CMD[0]} ${PREBUILD_CMD[*]:1}" 2>&1 | tee -a "$BUILD/00-prebuild.log"
    $TIME "$TOP/ci-scripts/${PREBUILD_CMD[0]}" "${PREBUILD_CMD[@]:1}" >> "$BUILD/00-prebuild.log" 2>&1
    log_stats "Prebuild" "$BUILD"
    echo "Prebuild: ${PREBUILD_CMD[*]}" >> "$STATFILE"

    echo "Build: ${BUILD_CMD[*]}" >> "$STATFILE"
    log "${BUILD_CMD[*]}" 2>&1 | tee "$BUILD/00-wrbuild.log"
    $TIME "${BUILD_CMD[@]}" 2>&1 | log_stdout >> "$BUILD/00-wrbuild.log"

    RET=${PIPESTATUS[0]}

    echo "FinishUTC: $(date +%s)" >> "$STATFILE"
    log_stats "Build" "$BUILD"

    if [ "$RET" != 0 ]; then
        log "Build failed"
        echo "Status: FAILED" >> "$STATFILE"
    else
        echo "Status: PASSED" >> "$STATFILE"

    fi
fi

trigger_postprocess "$STATFILE"

log "Done build"