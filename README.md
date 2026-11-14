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

# sdv_media_everyware_cf

SDV EveryWare on Cuttlefish: the product of the RB3 (`device/rb3/sdv_media_db845c`) in a
virtual machine on a Linux laptop. SDV core without the Java framework, the house's service
bundles, the smart home panel on virtio-gpu, Wi-Fi with DHCP. For development without a board
and for continuous builds. PLAN.md has the decisions and the alternatives.

## What the product is made of

| Piece | From | How |
|---|---|---|
| SDV core: init, apexd, servicemanager, keystore2, vold, the SDV services and agents | `device/google/sdv/sdv_core_base/sdv_core_base.mk` | included, as on the RB3 |
| The virtual board: x86_64, kernel 6.6 and its virtual-device modules, erofs in super, AVB with the test keys, boot HAL, serial log | `device/google/sdv/sdv_media_cf/BoardConfig.mk`, `sdv_cf/sdv_cf.mk`, `sdv_core_cf/fstab.sdv` | `BoardConfig.mk` includes Google's board config, as `sdv_har_cf` does; not `sdv_media_cf.mk`, which brings all of Google's samples |
| Graphics: ANGLE on gfxstream Vulkan, minigbm, no SurfaceFlinger | `device/google/sdv/sdv_media_base` | inherited; the panel drives the virtio-gpu display itself through `libgbm` |
| How the VM runs: one 1920x1080 display, GPU mode, memory, identity | Google's launch configuration `sdv_media_instance1` | named in `android-info.txt`, used by `cvd` |
| Device identity and service discovery for one device | Google's test DICE file, `vvmconfig.example`, the preprovisioned trust store image of instance1 | the mesh stays on the device: the agents' namespaces have loopback only (`ethernet/`), RPC on `lo` |
| Network: Wi-Fi, DHCP, names | `virt_wifi` on Cuttlefish's Wi-Fi tap (Google's `setup_wifi`), `wpa_supplicant`, AOSP's `dhcpclient`, `vendor/sdv-everyware/dnsproxyd` | `net/net_bringup.sh` |
| Time | `vendor/sdv-everyware/third_party/chrony` | started at boot |
| The house's services: weather, news, Wi-Fi, Matter, system, the dashboard bridge | `vendor/sdv-everyware/everyware/product/everyware.mk` | inherited; the domains of the Wi-Fi, Matter and System bundles in `sepolicy/` |
| The smart home panel | `packages/services/display_safety/utils/smarthome-app` | the vendor APEX `com.everyware.smarthome`, started by its own init script, in HAR's domain |
| Settings | SDV's `user_preferences` (sample APEX) | as on the RB3 |

Root init: `androidboot.init_rc` names `/system/etc/init/hw/init.sdv_media_everyware_cf.rc`, and
init reads that file and its imports only.

SELinux is permissive (the launch flag `--guest_enforce_security=false`), as on the RB3. The
identity is Google's public test identity of instance1. Both are for development.

## Build

```
CF_OUT_DISK=<mount point> source device/cf-everyware/sdv_media_everyware_cf/tools/env.sh
m
```

`tools/env.sh` sets `OUT_DIR=cuttlefish_out` and runs lunch; with `CF_OUT_DISK` the out
directory is a symlink to that disk. A full build takes about 60 GB. On a Cuttlefish board
(`vsoc_x86_64`) `m` also builds the host tools (`hosttar`: `launch_cvd`, `crosvm`, gfxstream).

## Run

Needs the host packages `cuttlefish-base` and `cuttlefish-user` (the `cvd` command, the host's
bridges and taps), and the user in the groups `kvm`, `cvdnetwork` and `render`.

```
device/cf-everyware/sdv_media_everyware_cf/tools/run.sh start
adb -s 0.0.0.0:6526 shell
device/cf-everyware/sdv_media_everyware_cf/tools/run.sh screenshot panel.png
device/cf-everyware/sdv_media_everyware_cf/tools/run.sh stop
device/cf-everyware/sdv_media_everyware_cf/tools/run.sh rm      # before a start with new images
```

The instance is group `everyware`, instance 7 (`CF_INSTANCE`): other Cuttlefish instances on the
host keep their numbers, ports and taps. `stop` and `rm` touch this group only. The display and
touch are in the browser at `https://localhost:1443` (Cuttlefish's WebRTC page). `cvd` runs the
tree's `run_cvd`, `assemble_cvd` and `crosvm`, and its own copies of the helper tools (WebRTC,
input, the adb proxy).

adb goes over vsock only (`service.adb.listen_addrs=vsock:5555`, as Cuttlefish's own devices):
without it adbd, which finds no USB gadget, would listen on TCP 5555 of `wlan0`, open to the
host's bridge.

The GPU: by default the host renders with SwiftShader (Google's launch configuration), which
works on any host and costs host CPU. `CF_GPU_MODE=gfxstream_guest_angle` renders on the host's
GPU; on an AMD GPU with RADV that needs two changes of the host tools that are not upstream (the
AMD check in `device/google/cuttlefish/host/commands/assemble_cvd/graphics_flags.cc`, and the
tiling of dma-buf images in `hardware/google/gfxstream`, switched on with
`GFXSTREAM_DMABUF_IMAGES_OPTIMAL=1` in the environment of `cvd`).

## Network

The host gives each instance a tap on its Wi-Fi bridge (`cvd-wbr`, 192.168.96.0/24, DHCP and NAT
on the host). `android-info.txt` asks for that tap (`enforce_mac80211_hwsim=false`), and in the
guest it is `eth2`.

```
init (on boot)
  └─ start vendor.net_bringup      net/net_bringup.sh
       ├─ setup_wifi --interface=eth2   eth2 -> buried_eth2 with this instance's MAC,
       │                                wlan0 = virt_wifi on top: one open network, VirtWifi
       ├─ /data/vendor/wifi/wpa_supplicant.conf missing? write it with VirtWifi
       ├─ wpa_supplicant -iwlan0 -g@abstract:wpa_everyware   (the Wi-Fi bundle's socket)
       ├─ watchdog: scan while not connected; on connect dhcpclient -i wlan0
       └─ wait
dhcpclient: address, default route, MTU; vendor.net.wlan0.gw, vendor.net.wlan0.dns1..4
dnsproxyd:  resolves with vendor.net.wlan0.dns*
chronyd:    refreshes its servers when dns1 is set
```

The host must answer DHCP on `cvd-wbr`. With firewalld, a bridge in no zone falls into the
default zone `public`, which does not let DHCP in: the guest associates with `VirtWifi` but gets
no lease. Then the bridges need a zone that allows the `dhcp` service (root, on the host).

Where the host's firewall cannot be changed, `CF_STATIC_WIFI=1 tools/run.sh start` gives the
address from the host instead, as Cuttlefish does for its mobile network: run.sh takes the
network of `cvd-wbr` and puts `everyware.wlan0=<address>/<prefix>,<gateway>,<dns>...` on the
kernel command line (address 100 + the instance number, the bridge as gateway, DNS as the
host's dnsmasq hands out). net_bringup.sh then runs `wlan_static` instead of dhcpclient on
connect; it sets the address and the default route and publishes the same `vendor.net.wlan0.*`.

On the RB3 the config holds the house's network and is written by the user; here the only
network is the VM's own open one, so the script writes it. The Wi-Fi bundle sees `VirtWifi` in
its scan and can join it again.

The SDV agents do not use the Ethernet tap (`eth1`, Google's mesh): discovery and RPC stay on
the device, as on the RB3.

## What differs from the RB3

| | RB3 | Cuttlefish |
|---|---|---|
| Board files | Linaro's `db845c` | Google's SDV Media on Cuttlefish |
| GPU and display | Mesa freedreno, the msm display controller over HDMI | ANGLE on gfxstream (host SwiftShader or host GPU), virtio-gpu |
| Touch | USB HID panel, 0..32767 (`--touch-size 1920x1080` scales it) | virtio multi-touch in display pixels (the same flag maps 1:1) |
| Wi-Fi | ath10k with the modem firmware, the house's network | `virt_wifi` on the host's Wi-Fi bridge, `VirtWifi` |
| Identity and trust store | in the image's bootconfig, the trust store from `/product/etc` | from the launch configuration, the trust store from an image the host attaches |
| SELinux mode | `androidboot.selinux` in the image | the launch flag |
| Clock at boot | no RTC battery: chronyd restores the last time | the host's time |
| Kernel modules | Linaro's: disk and display in the first stage, the rest in the background | Google's virtual-device modules, all in the first stage |
| Not here | | the Qualcomm remote processors, Bluetooth, the audio HAL, the browser |

## State

2026-11-14, first runs on a laptop with an AMD GPU, host SwiftShader, `cvd` 1.53:

| Check | Result |
|---|---|
| Build | `m` passes (images and host tools); needed one fix in `vendor/sdv-everyware/third_party/rust` (chacha20 on Android x86-64) |
| Boot | `sys.boot_completed=1`, `ro.sdv.orchestrator.state.ready=true`, SELinux permissive, instance1, RPC on `lo` |
| SDV agents | lifecycle, orchestration, service discovery, RPC, data tunnel, health, update manager, vpm, vsidl provider running |
| Bundles | weather, news, Wi-Fi, Matter, system, dashboard and `user_preferences` running, each in its SELinux domain |
| Wi-Fi | `setup_wifi` makes `wlan0`, the supplicant joins `VirtWifi`, the Wi-Fi bundle reports it (`WIFI_CONNECTED "VirtWifi" 4 bars`), the panel's Wi-Fi sheet lists it |
| DHCP | no lease on this host: its firewall drops DHCP on `cvd-wbr` (see Network); with the lease set by hand, dnsproxyd resolves, chronyd syncs (stratum 1), weather and news arrive over HTTPS |
| Panel | with harry's fix for a plane without zpos (below) it starts with the APEX's `--zone-plane`; `ro.vendor.everyware.zone_plane=false` turns zone planes off; idle, it draws 1 frame a second (the clock) |
| Touch | a click in the WebRTC page goes through crosvm's virtio multi-touch to the panel: tabs and the Wi-Fi sheet open |
| Resources | the guest uses 1 of its 2 GB; on the host crosvm takes about a quarter of a core with an idle panel (it took ~5 cores while the panel redrew 30 times a second without the property) |
| Enforcing (`CF_ENFORCE=true`) | boots, but the orchestrator never gets ready, 2 of 7 bundles start, the panel and the mesh script are denied |

What does not work yet, and where the change belongs:

1. The panel's init script passes `--zone-plane`; harry then set the primary plane's `zpos`
   (`packages/services/display_safety/framework/graphics/har-gl-context/src/direct_rendering/kms.rs`,
   `plane_props["zpos"]`), and virtio-gpu's planes have no `zpos`: the lookup panicked and init
   restarted the panel in a loop. Fixed on branches, not landed yet: harry sets `zpos` only when
   the plane has it (super-harry `feature/zpos-optional`), and the panel reads
   `ro.vendor.everyware.zone_plane` (smarthome-app `feature/board-zone-plane`). Until they land,
   an image built from main still has the crash.
2. DHCP on this host: a firewall setting of the host, not of the image.
3. Enforcing: the policy of the panel, of the bundles' name lookups and of the mesh script is
   not written yet (the same holds for the RB3, which runs permissive).
