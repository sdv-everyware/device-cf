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

# The board is Google's SDV Media on Cuttlefish, as device/google/sdv_display_safety/sdv_har_cf
# takes it for HAR: x86_64, the 6.6 kernel and its virtual-device modules, virtio-gpu, the
# partitions, AVB with the test keys. Set before the include: Google's files take the first value.

# the root init: init reads this file and its imports only
LOCAL_ANDROIDBOOT_INIT_RC := /system/etc/init/hw/init.sdv_media_everyware_cf.rc
# the SDV RPC servers bind to this interface's address: loopback keeps them on the device, as
# on the RB3. Google's targets use a VLAN on the Ethernet tap, which reaches every Cuttlefish
# instance on the host's bridge.
SDV_RPC_INTERFACE := lo

include device/google/sdv/sdv_media_cf/BoardConfig.mk

# Wi-Fi: virt_wifi, a station on top of the Wi-Fi tap, and what it needs
BOARD_VENDOR_RAMDISK_KERNEL_MODULES += \
    $(SYSTEM_DLKM_SRC)/rfkill.ko \
    $(KERNEL_MODULES_PATH)/cfg80211.ko \
    $(KERNEL_MODULES_PATH)/virt_wifi.ko

# HAR's domain vendor_harplatform for the panel's UI process (vendor file types: the vendor
# policy, as on the RB3). Before the product's own folder: that one adds to vendor_harplatform.
BOARD_VENDOR_SEPOLICY_DIRS += packages/services/display_safety/service/product/sepolicy

BOARD_VENDOR_SEPOLICY_DIRS += device/cf-everyware/sdv_media_everyware_cf/sepolicy/vendor
