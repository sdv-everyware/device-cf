#!/usr/bin/env bash
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Runs the built image as its own Cuttlefish instance group, next to any other instance on the
# host: its own group name and instance number, stopped by name. Never `cvd reset` or
# `cvd clear` here: they stop every instance of the user.
#
#     device/cf-everyware/sdv_media_everyware_cf/tools/run.sh start
#     device/cf-everyware/sdv_media_everyware_cf/tools/run.sh screenshot panel.png
#     device/cf-everyware/sdv_media_everyware_cf/tools/run.sh stop
#     device/cf-everyware/sdv_media_everyware_cf/tools/run.sh rm      (the group and its disks)
#
# start takes Google's launch configuration that android-info.txt names (sdv_media_instance1:
# one 1920x1080 display, gfxstream with host SwiftShader, instance1 of the development mesh)
# and changes only what is listed below. Environment:
#   CF_INSTANCE  instance number (default 7: adb on port 6520+N-1, the host's taps cvd-*-0N)
#   CF_GROUP     group name (default everyware)
#   CF_GPU_MODE  another --gpu_mode, e.g. gfxstream_guest_angle for the host GPU (README.md)
#   CF_ENFORCE   true for SELinux enforcing (default false: permissive, as the RB3)

set -euo pipefail

TREE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
OUT="$TREE/${OUT_DIR:-cuttlefish_out}"
HOST_OUT="$OUT/host/linux-x86"
PRODUCT_OUT="$OUT/target/product/sdv_media_everyware_cf"
INSTANCE="${CF_INSTANCE:-7}"
GROUP="${CF_GROUP:-everyware}"
SERIAL="0.0.0.0:$((6520 + INSTANCE - 1))"

case "${1:-}" in
start)
    [ -x "$HOST_OUT/bin/launch_cvd" ] || { echo "no host tools in $HOST_OUT: m (or m hosttar)"; exit 1; }
    [ -f "$PRODUCT_OUT/super.img" ] || { echo "no image in $PRODUCT_OUT: m"; exit 1; }
    if cvd fleet 2>/dev/null | grep -q "\"group_name\" : \"$GROUP\""; then
        echo "group $GROUP exists: $0 rm first (or $0 stop and cvd -group_name $GROUP start)"
        exit 1
    fi
    args=(
        --host_path="$HOST_OUT"
        --product_path="$PRODUCT_OUT"
        --base_instance_num="$INSTANCE"
        # SELinux as on the RB3: permissive while the denials are collected
        --guest_enforce_security="${CF_ENFORCE:-false}"
        # nothing leaves the host
        --report_anonymous_usage_stats=n
        # The streamer writes each display's frames into a shm ring
        # (/dev/shm/cf_shmem_display_*) that a host viewer reads directly (cfview),
        # but it keeps the rings only when a display has overlays
        # (frontend/webrtc/main.cpp, OverlaysEnabled). "0:0" lays the display over
        # itself: the picture does not change, one blend per new frame. To be
        # replaced by a viewer that takes crosvm's frames itself.
        --display0=width=1920,height=1080,overlays=0:0
    )
    [ -n "${CF_GPU_MODE:-}" ] && args+=(--gpu_mode="$CF_GPU_MODE")
    cvd -group_name "$GROUP" create "${args[@]}"
    echo "adb -s $SERIAL"
    ;;
stop)
    cvd -group_name "$GROUP" stop
    ;;
rm)
    # before a start with new images: the group's overlay and data go with it
    cvd -group_name "$GROUP" rm
    ;;
status)
    cvd -group_name "$GROUP" fleet
    ;;
screenshot)
    # what the display shows, from the host side of the virtual display (no SurfaceFlinger in
    # the guest for adb screencap)
    path="$(realpath -m "${2:?screenshot <file.png>}")"
    cvd -group_name "$GROUP" display screenshot --screenshot_path="$path"
    ;;
*)
    echo "usage: $0 start|stop|rm|status|screenshot <file.png>"
    exit 1
    ;;
esac
