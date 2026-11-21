<!--
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
-->

# sdv_media_everyware_cf: plan and decisions

Goal: on Cuttlefish the same system as on the RB3 (`device/rb3/sdv_media_db845c`): SDV core
without the Java framework, the house's service bundles (weather, news, calendar, Wi-Fi, Matter,
system, dashboard), the panel from its vendor APEX (`com.everyware.smarthome`) with Wayland zones,
its child processes (`camera-app`, optional `doom-app` and browser) and touch, Wi-Fi with DHCP,
names (dnsproxyd), time (chrony), settings in `user_preferences`. One image that a laptop runs
without a board, for development and for continuous builds.

## The reference: how Google runs SDV on Cuttlefish

| What | Google | Where |
|---|---|---|
| Products | `sdv_core_cf`, `sdv_media_cf`, `sdv_ivi_cf`: samples, "not meant to be extended by OEM targets"; an OEM target takes `sdv_core_base`, `sdv_media_base` and `sdv_cf` | `device/google/sdv/sdv_*_cf/*.mk` |
| A product on top of SDV Media | `sdv_media_har_cf` (HAR): inherits `sdv_media_cf.mk`, its own board folder includes `sdv_media_cf/BoardConfig.mk` and sets its root init first | `device/google/sdv_display_safety` |
| Board | x86_64, kernel 6.6 with the virtual-device modules in the first stage, erofs in super, AVB with the test keys, virtio-gpu, root init by `androidboot.init_rc` | `sdv_core_base/BoardConfig.mk`, `sdv_core_cf/BoardConfig.mk`, `sdv_media_cf/BoardConfig.mk` |
| Graphics | ANGLE on gfxstream Vulkan, minigbm, no SurfaceFlinger | `sdv_media_base/sdv_media_base.mk`, `init.sdv_media_base.rc` |
| Launching | `cvd create` with a launch configuration that `android-info.txt` names: `sdv_media_instance1` = one 1920x1080 display, `gfxstream_guest_angle_host_swiftshader`, 2 GB, and the identity of instance1 of the development mesh as extra bootconfig | `sdv_media_cf/config/` |
| Network | Ethernet tap `eth1` (192.168.98.x) with VLANs for service discovery, data tunnel and RPC, the agents in their network namespaces; MACsec sample | `sdv_cf/ethernet/`, `sdv_base/ethernet/` |
| Identity | DICE from a test file, the trust store from a preprovisioned image the host attaches | `init_open_dice_from_file.mk`, `vvmtruststore_preprovisioned/` |

## Decisions

| # | Decision | Chosen | Alternatives | Why |
|---|---|---|---|---|
| C1 | Folder and name | `device/cf-everyware/sdv_media_everyware_cf`, product `sdv_media_everyware_cf` | a product in `device/google/sdv` | no file of Google's edited; the build finds every `device/*/*/AndroidProducts.mk`; no clash with Google's names |
| C2 | Product layers | Google's reusable parts: `sdv_core_base.mk`, `sdv_cf.mk`, `sdv_media_base.mk`, Google's `fstab.sdv`, plus the RB3's product list | inherit `sdv_media_cf.mk`, as `sdv_media_har_cf` does | `sdv_media_cf.mk` brings all of Google's samples (car samples, SOME/IP, the OEM updater and its partitions, MACsec, a sample `service_bundle_contexts` that collides with the house's); its header says to use the base files; the RB3 has none of them |
| C3 | Board | includes `sdv_media_cf/BoardConfig.mk`, with the root init and the RPC interface set before it | `sdv_core_cf` and `sdv_media_base` board files one by one | the way `sdv_har_cf` takes it; Google's files use `?=` for exactly these two |
| C4 | Launch configuration | Google's `sdv_media_instance1`, named in `android-info.txt`; `tools/run.sh` adds only the SELinux mode, the instance number and the group name | a launch configuration of our own; the identity in the image's bootconfig, as on the RB3 | Google's way on Cuttlefish; the image holds no identity; a key both in the image and from the host is a duplicate, and the kernel then drops the whole bootconfig |
| C5 | SDV mesh | on the device: the agents' namespaces with loopback only (`ethernet/`), `androidboot.sdv.rpc.interface=lo` | Google's VLANs on `eth1` (`init.sdv_cf.rc`) | one device, as the RB3; Google's mesh puts discovery and RPC on the host bridge `cvd-ebr`, where every other Cuttlefish instance of the host is, with the addresses and the identity (instance1) other SDV setups on the same host use |
| C6 | Wi-Fi | `virt_wifi` on the Wi-Fi tap (`eth2`) by Google's `setup_wifi`, then the RB3's chain: `wpa_supplicant` with the control socket for the Wi-Fi bundle, `dhcpclient`, `vendor.net.wlan0.*` | Cuttlefish's default `mac80211_hwsim` with `wmediumd` and an OpenWRT access point; DHCP on `eth1` | the RB3's chain stays as it is (the Wi-Fi bundle, dnsproxyd reads `wlan0` only, the chrony refresh); `hwsim` needs the OpenWRT images on the host and more modules; `eth1` leaves the Wi-Fi bundle without a supplicant. `enforce_mac80211_hwsim=false` in `android-info.txt` gives the guest the tap |
| C7 | The supplicant's config | written at the first boot with the open network `VirtWifi` | an empty config, the network joined from the panel | `VirtWifi` is the virtual hardware, no secret; the network is up at boot, as on an RB3 after its setup |
| C8 | GPU on the host | Google's default, SwiftShader on the host (`gfxstream_guest_angle_host_swiftshader`) | `gfxstream_guest_angle` on the host GPU (`CF_GPU_MODE`) | works on any host without changes; with an AMD GPU and RADV the host GPU needs two local changes of the host tools (the AMD check in `graphics_flags.cc`, the image tiling in gfxstream with `GFXSTREAM_DMABUF_IMAGES_OPTIMAL=1`) |
| C9 | SELinux | permissive, by the launch flag `--guest_enforce_security=false` | enforcing; `androidboot.selinux` in the image as on the RB3 | as the RB3 while the denials are collected; on Cuttlefish the host sets the key, so the same image boots enforcing with `CF_ENFORCE=true` |
| C10 | Out directory | `cuttlefish_out`, a symlink to the second disk (`CF_OUT_DISK`) | in the tree on the 4 TB disk | a full out directory is 70 to 130 GB here; the tree's disk had 46 GB free |
| C11 | Host tools | built from this tree (`m` builds `hosttar` on a `vsoc_x86_64` board), started by the installed `cvd` | the host package of the installed `cuttlefish-base` | guest and host gfxstream from one tree; `cvd` 1.53 keeps the tree's `run_cvd`, `assemble_cvd`, crosvm and gfxstream and runs its own copies of the helper tools (WebRTC, input, the adb proxy) |
| C12 | Instance | group `everyware`, instance 7 (`CF_INSTANCE`) | the next free number | other instances keep their numbers, ports and taps (the three-VM demo uses 1 to 3); `tools/run.sh stop` stops this group only |
| C13 | Browser | off by default (`EVERYWARE_BROWSER=true` enables it), permissive `everyware_browser` policy and 4 GiB `/data` when on | always in the image | experimental (known security issues); matches `device-rb3` (`init.sdv_media_everyware_cf.browser.rc`) |
| C14 | Not taken from the RB3 | Linaro's board files, the Qualcomm remote processors, the Bluetooth HAL, the AIDL audio HAL, Mesa freedreno | | the board's hardware; Cuttlefish has no Bluetooth without netsim, and nothing here plays audio through the HAL |
| C15 | adb | over vsock only: `service.adb.listen_addrs=vsock:5555`, as Cuttlefish's own devices (`device/google/cuttlefish/shared/device.mk`) | Google's SDV targets, which leave it unset | adbd finds no USB gadget and then listens on TCP 5555 of every interface: `wlan0` is on the host's bridge, and a userdebug adbd asks for no key; the host's adb proxy uses vsock anyway |
| C16 | Vendor shell | `sh_vendor` and `toybox_vendor`, as on the RB3 | `/system/bin/sh` in the script | the vendor script runs from `/vendor`; Google's SDV vendor partition has no shell, and init fails the service with "No such file or directory" |

## What comes from where

| Part | From |
|---|---|
| SDV core, the sample policies, DICE from a file | `device/google/sdv`, as in `sdv_media_db845c.mk` |
| Cuttlefish board, boot HAL, serial log, trust store image | `device/google/sdv/sdv_media_cf/BoardConfig.mk`, `sdv_cf/sdv_cf.mk`, `vvmtruststore_preprovisioned/` |
| Graphics | `device/google/sdv/sdv_media_base` |
| `wlan0` | `device/google/cuttlefish/guest/commands/setup_wifi` and the virtual-device modules `cfg80211`, `virt_wifi` (with GKI's `rfkill`) |
| House's bundles, dnsproxyd, chrony | `vendor/sdv-everyware`, inherited as on the RB3 |
| The panel and its child processes | `com.everyware.smarthome` from `smarthome-app`, `camera-app` (`product/camera.mk`), optional `doom-app` (`product/doom.mk`) |
| Copied and adapted from `device/rb3/sdv_media_db845c` | `sepolicy/system_ext/*` (same), `sepolicy/vendor/*.te` and `property_contexts` (without KeyMint and dragonboard-specific types), `vintf/`, `ethernet/`, `net/net_bringup.sh` (with `setup_wifi`, `wlan_static` and the default config, without the modem), the root init (Cuttlefish's imports) |
| New | `BoardConfig.mk`, `android-info.txt`, `init.everyware_cf.rc`, `net/wlan_static.cpp`, `tools/` |

## State

See README.md, "State": builds and runs cleanly from `main` with live bundles, display and touch;
what remains open is SELinux enforcing policy (shared with the RB3) and host firewall DHCP rules
(worked around with `CF_STATIC_WIFI=1`).
