#!/system/bin/sh
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
# The network namespaces of the SDV agents (service discovery, data tunnel) on one device:
# in a car each holds a VLAN to the other machines, here loopback only.
set -e
for ns in sd_mesh_ns sdv_dt_ns; do
  ip netns add "$ns"
  ip -n "$ns" link set lo up
done
log -t boot-timing -p i "sdv-sd-mesh-local has started successfully"
