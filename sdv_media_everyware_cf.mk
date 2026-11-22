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

# sdv_media_everyware_cf: SDV EveryWare on Cuttlefish. The product of the RB3
# (device/rb3/sdv_media_db845c): SDV core without the Java framework, the house's service
# bundles, the panel from its vendor APEX, Wi-Fi with DHCP, names and time. The board is Google's
# SDV Media on Cuttlefish (sdv_media_base, sdv_cf, the board config of sdv_media_cf), without
# Google's samples. PLAN.md has the decisions, README.md what differs from the RB3.

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, device/google/cuttlefish/vsoc_x86_64/bootloader.mk)

# How cvd runs the image: Google's launch configuration of SDV Media (one 1920x1080 display,
# gfxstream with ANGLE in the guest, 2 GB) as instance1 of Google's development mesh (its test
# identity and trust store). android-info.txt names it.
$(call soong_config_append,cvd,launch_configs,cvd_config_sdv_media.json)
$(call soong_config_append,cvd,launch_configs,cvd_config_sdv_media_instance1.json)
TARGET_BOARD_INFO_FILE := device/cf-everyware/sdv_media_everyware_cf/android-info.txt

# as sdv_core_cf.mk and the RB3; the core base errors without them
SDV_VM_LEVEL_PERMISSIONS_MODULE := com.oem.sdv.authz.allow_all.core
SDV_SOMEIP_BROKER_CONFIG := broker_config.json
PRODUCT_SYSTEM_PROPERTIES += ro.sdv.someip.broker_config=/system/etc/someip/broker_config.json
# keystore2 needs a KeyMint; Cuttlefish has no TEE for SDV, so SDV's nonsecure one
PRODUCT_PACKAGES += android.sdv.hardware.security.keymint-service.nonsecure
SDV_VEHICLE_POWER_STATE_MANAGER_MODULE := vepsm
SDV_DIAGNOSTICS_AGENT_MODULE := sdv_diagnostics_agent

include device/google/sdv/sdv_core_base/sdv_core_base.mk

# Google's reusable parts of an SDV target on Cuttlefish: the boot HAL, the serial log, the
# mount of the trust store partition. Its Ethernet mesh (init.sdv_cf.rc) is installed but not
# imported by the root init: the SDV mesh stays on the device (ethernet/).
include device/google/sdv/sdv_cf/sdv_cf.mk

# SDV Media on Cuttlefish: ANGLE on gfxstream Vulkan, minigbm, the media profile
$(call inherit-product, device/google/sdv/sdv_media_base/sdv_media_base.mk)

# the partitions and their fstab, as sdv_core_cf.mk (fstab.<androidboot.hardware>)
PRODUCT_COPY_FILES += \
    device/google/sdv/sdv_core_cf/fstab.sdv:$(TARGET_COPY_OUT_VENDOR_RAMDISK)/first_stage_ramdisk/fstab.sdv \
    device/google/sdv/sdv_core_cf/fstab.sdv:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.sdv

# The screen link between the panel (vendor) and the dashboard bundle (product): VINTF checks a
# vendor HAL against a framework matrix, and its client lives on /product.
DEVICE_PRODUCT_COMPATIBILITY_MATRIX_FILE += device/cf-everyware/sdv_media_everyware_cf/vintf/product_compatibility_matrix.xml

PRODUCT_COPY_FILES += \
    device/google/sdv/sdv_core_arm64/sdv_product_native_services_names:$(TARGET_COPY_OUT_PRODUCT)/etc/sdv_native_services_names

# adb over vsock only, as Cuttlefish's own devices (device/google/cuttlefish/shared/device.mk):
# the host reaches it through its vsock proxy. Without the property adbd, which finds no USB
# gadget here, listens on TCP 5555 on every interface, and so on wlan0 on the host's bridge.
PRODUCT_SYSTEM_PROPERTIES += service.adb.listen_addrs=vsock:5555

PRODUCT_NAME := sdv_media_everyware_cf
PRODUCT_DEVICE := sdv_media_everyware_cf
PRODUCT_BRAND := Android
PRODUCT_MODEL := SDV EveryWare on Cuttlefish
PRODUCT_MANUFACTURER := Google

# harry's renderer, for an app run from /data/local/tmp during development
PRODUCT_PACKAGES += libimpeller

# net/net_bringup.sh is a vendor script: it needs a vendor shell and toybox (log, grep, sed),
# which Cuttlefish's SDV vendor partition does not have
PRODUCT_PACKAGES += \
    sh_vendor \
    toybox_vendor

# Wi-Fi: Cuttlefish's Wi-Fi tap with virt_wifi on top (Google's setup_wifi, as on Cuttlefish
# phones) and wpa_supplicant without the framework, started by net/net_bringup.sh
FORCE_USE_ANDROIDMK_FOR_WPA_CONF := true
PRODUCT_PACKAGES += \
    setup_wifi \
    wpa_supplicant \
    wpa_supplicant.conf \
    wpa_cli

# the board's init without the framework: Wi-Fi, DHCP and the clock
PRODUCT_COPY_FILES += \
    device/cf-everyware/sdv_media_everyware_cf/init.everyware_cf.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/init.everyware_cf.rc

# network without the framework: AOSP's dhcpclient (Trusty's, in a Soong namespace) and the script
PRODUCT_SOONG_NAMESPACES += device/generic/trusty
PRODUCT_PACKAGES += dhcpclient
# the address from the host instead, where the host's firewall drops DHCP (net/wlan_static.cpp)
PRODUCT_SOONG_NAMESPACES += device/cf-everyware/sdv_media_everyware_cf/net
PRODUCT_PACKAGES += wlan_static
PRODUCT_COPY_FILES += \
    device/cf-everyware/sdv_media_everyware_cf/net/net_bringup.sh:$(TARGET_COPY_OUT_VENDOR)/bin/net_bringup.sh

# SDV on one device: the sample policies, the test identity, service discovery on loopback
include device/google/sdv/sdv_core_base/sepolicy/samples/device_sepolicy.mk

# identity: instance1 of Google's development mesh, DICE from a test file, the trust store from
# its preprovisioned image (the launch configuration). Test secrets, development only
include device/google/sdv/sdv_base/init_open_dice/init_open_dice_from_file.mk
include device/google/sdv/vvmtruststore_preprovisioned/vvmtruststore_preprovisioned.mk
PRODUCT_PACKAGES += vvmconfig.example

# the network namespaces the SDV agents enter, with loopback only: no mesh on one device
PRODUCT_COPY_FILES += \
    device/cf-everyware/sdv_media_everyware_cf/ethernet/ethernet_sd_mesh_local.sh:$(TARGET_COPY_OUT_PRODUCT)/bin/ethernet/ethernet_sd_mesh_local.sh

include device/google/sdv/sdv_media_base/sdv_samples_media.mk

# name resolution without netd
$(call inherit-product, vendor/sdv-everyware/dnsproxyd/dnsproxyd.mk)

# the clock over NTP, restored from the last run at boot
$(call inherit-product, vendor/sdv-everyware/third_party/chrony/chrony.mk)

# the service bundles of the house (weather, news, calendar, Wi-Fi, Matter, system, the dashboard
# bridge), one APEX each, and the contexts that put them into their SELinux domains
$(call inherit-product, vendor/sdv-everyware/everyware/product/everyware.mk)

# the root init (androidboot.init_rc in BoardConfig.mk): init reads this file and its imports
# only. With the panel's experimental browser (EVERYWARE_EXPERIMENTAL_BROWSER=true, everyware.mk above) a
# root init of two lines takes its path: it imports the board's init and the browser's service.
ifeq ($(EVERYWARE_EXPERIMENTAL_BROWSER),true)
PRODUCT_COPY_FILES += \
    device/cf-everyware/sdv_media_everyware_cf/init.sdv_media_everyware_cf.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/hw/init.sdv_media_everyware_cf.board.rc \
    device/cf-everyware/sdv_media_everyware_cf/init.sdv_media_everyware_cf.browser.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/hw/init.sdv_media_everyware_cf.rc
else
PRODUCT_COPY_FILES += \
    device/cf-everyware/sdv_media_everyware_cf/init.sdv_media_everyware_cf.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/hw/init.sdv_media_everyware_cf.rc
endif

# virtio-gpu has no plane a zone can go under (no zpos): the panel's init script passes
# --zone-plane for every board, this turns it off, and the dashboard draws the zones, only on a
# client's new frame (smarthome-app README, Options)
PRODUCT_VENDOR_PROPERTIES += ro.vendor.everyware.zone_plane=false

# the domains of the bundles that do more than the default one: the Wi-Fi bundle talks to the
# supplicant's control socket, the Matter bundle has UDP and multicast, the System bundle sets
# the time zone; the supplicant's side of the socket is in sepolicy/vendor
SYSTEM_EXT_PUBLIC_SEPOLICY_DIRS += device/cf-everyware/sdv_media_everyware_cf/sepolicy/system_ext/public
SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS += device/cf-everyware/sdv_media_everyware_cf/sepolicy/system_ext/private

# The device's settings: SDV's user_preferences keeps them and asks the service that owns one to
# apply it (the System bundle owns the time zone). Google ships the service only as a sample
# APEX; with it come three car samples (HVAC, seats, an HMI) that start only in a test group.
PRODUCT_PACKAGES += com.android.sdv.sample.user_preferences

# the panel: a vendor APEX with its harry app, started by its own init script (smarthome-app's
# apex/). The app keeps HAR's domain vendor_harplatform (BoardConfig.mk), and the bundles bind
# TCP sockets (the dashboard's gRPC): HAR's own policy, as harry_apex/product.mk wires it
PRODUCT_PACKAGES += com.everyware.smarthome
SYSTEM_EXT_PUBLIC_SEPOLICY_DIRS += packages/services/display_safety/service/product/har_sdv_service_bundle_apex/lifecycle/sepolicy/public
SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS += packages/services/display_safety/service/product/har_sdv_service_bundle_apex/lifecycle/sepolicy

# the panel's camera (packages/services/display_safety/utils/camera-app): camera_app and its
# service, started when the panel runs (init.sdv_media_everyware_cf.rc imports
# /vendor/etc/init/everyware), in its domain everyware_camera (sepolicy/vendor). The emulator has
# no camera, so the tile shows the app's clip. A checkout without the camera-app repository has
# no camera.
$(call inherit-product-if-exists, packages/services/display_safety/utils/camera-app/product/camera.mk)

# the panel's game (DOOM, packages/services/display_safety/utils/doom-app): experimental and off
# unless EVERYWARE_GAME=true; then doom_app, Freedoom's WAD (fetched before the build), its
# service (started when the panel runs, in its domain everyware_game) and the property by which
# the panel shows its game button. A checkout without the doom-app repository has no game,
# whatever the flag says.
$(call inherit-product-if-exists, packages/services/display_safety/utils/doom-app/product/doom.mk)

# adb remount on a userdebug build, as on the RB3: the core base of this tree does not ship the
# tools of the overlay on /data yet
PRODUCT_PACKAGES_DEBUG += \
    remount \
    overlay_remounter \
    gsid
