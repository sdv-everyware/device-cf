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

# Build environment for sdv_media_everyware_cf. Source it, do not execute it: lunch and OUT_DIR
# have to land in the calling shell.
#
#     source device/cf-everyware/sdv_media_everyware_cf/tools/env.sh
#     m
#
# OUT_DIR is cuttlefish_out, one out directory for this product: a product switch inside a
# shared out directory rebuilds thousands of steps. Set CF_OUT_DISK to a mount point to keep the
# directory on another disk; the tree then gets a symlink to it (Soong rejects an absolute out
# directory outside the tree).

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "source me, do not execute: source ${0}"
  exit 1
fi

TREE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
export OUT_DIR="${OUT_DIR:-cuttlefish_out}"

if [ -n "${CF_OUT_DISK:-}" ]; then
  if ! mountpoint -q "$CF_OUT_DISK"; then
    echo "CF_OUT_DISK=$CF_OUT_DISK is not a mount point. Not sourcing."
    return 1
  fi
  if [ -e "$TREE/$OUT_DIR" ] && [ ! -L "$TREE/$OUT_DIR" ]; then
    echo "$TREE/$OUT_DIR exists and is not a symlink. Not sourcing."
    return 1
  fi
  mkdir -p "$CF_OUT_DISK/$OUT_DIR"
  [ -L "$TREE/$OUT_DIR" ] || ln -s "$CF_OUT_DISK/$OUT_DIR" "$TREE/$OUT_DIR"
fi

cd "$TREE" || return 1
source build/envsetup.sh
lunch sdv_media_everyware_cf-trunk_staging-userdebug || return 1
echo "OUT_DIR=$OUT_DIR"
