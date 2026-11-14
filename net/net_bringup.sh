#!/vendor/bin/sh
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

# Wi-Fi with DHCP without the framework, started by init.everyware_cf.rc. The RB3's script
# (device/rb3/sdv_media_db845c/net/net_bringup.sh) on Cuttlefish's Wi-Fi: the host gives the
# VM a tap on its Wi-Fi bridge (eth2 in the guest, DHCP and NAT on the host), and virt_wifi
# makes wlan0 on top of it, a station that sees one open network, VirtWifi. wpa_supplicant and
# dhcpclient run as children of this script (init kills the process group when the main process
# exits); dhcpclient sets address, route and MTU and publishes the gateway and the DNS servers as
# vendor.net.wlan0.*, which dnsproxyd and chronyd read.
#
# everyware.wlan0=<address>/<prefix>,<gateway>,<dns>[,<dns>...] on the kernel command line
# (tools/run.sh, CF_STATIC_WIFI=1): the host chose the address, for a host whose firewall drops
# DHCP on the bridge; wlan_static sets it and publishes the same properties, no dhcpclient.

log() { /vendor/bin/log -t net_bringup "$*"; }

static=
for word in $(cat /proc/cmdline); do
    case "$word" in everyware.wlan0=*) static=${word#everyware.wlan0=} ;; esac
done

sockets=/data/vendor/wifi/wpa/sockets

wait_iface() {
    i=0
    while [ ! -e /sys/class/net/$1 ]; do
        [ $i -ge $2 ] && return 1
        sleep 1
        i=$((i + 1))
    done
}

# The supplicant (built for the framework) scans only on command: a scan every 5 s while not
# connected. dhcpclient on every connect, not before: started early its DISCOVERs go nowhere
# and it backs off for seconds. From here as root: wpa_cli's action script would run as wifi.
wifi_watchdog() {
    wpa="/vendor/bin/wpa_cli -p $sockets -i wlan0"
    dhcp=
    connected=no
    tick=25
    while true; do
        # a plain STATUS would re-send the connected events to every monitor
        case "$($wpa raw STATUS-NO_EVENTS 2>/dev/null)" in
            *wpa_state=COMPLETED*)
                if [ $connected = no ]; then
                    connected=yes
                    if [ -n "$static" ]; then
                        # shellcheck disable=SC2086 -- the values are split on purpose
                        /vendor/bin/wlan_static wlan0 $(echo "$static" | sed 's/,/ /g') &&
                            log "wlan0 connected, address from the host: $static" ||
                            log "wlan0 connected, wlan_static failed"
                    else
                        [ -n "$dhcp" ] && kill $dhcp 2>/dev/null
                        /vendor/bin/dhcpclient -i wlan0 &
                        dhcp=$!
                        log "wlan0 connected, dhcpclient started"
                    fi
                fi
                sleep 1 ;;
            *wpa_state=SCANNING*|*wpa_state=*ASSOCIATING*|*wpa_state=AUTHENTICATING*|*HANDSHAKE*)
                connected=no
                sleep 0.2 ;;
            *)
                connected=no
                if [ $tick -ge 25 ]; then
                    $wpa scan > /dev/null && log "wlan0 not connected, scan"
                    tick=0
                fi
                tick=$((tick + 1))
                sleep 0.2 ;;
        esac
    done
}

# wlan0: Google's setup_wifi renames eth2 to buried_eth2, gives it the MAC of this instance
# (androidboot.wifi_mac_prefix) and adds the virt_wifi link
if [ ! -e /sys/class/net/wlan0 ]; then
    if ! wait_iface eth2 20; then
        log "no eth2: the instance has no Wi-Fi tap (enforce_mac80211_hwsim=false in android-info.txt)"
    elif /vendor/bin/setup_wifi --interface=eth2; then
        log "wlan0 on eth2 (virt_wifi)"
    else
        log "setup_wifi failed"
    fi
fi

# The config is created on the device, never in the image. On the RB3 the user writes it (the
# SSID and passphrase of the house); here the one network of the VM is open, so a missing config
# is written with it: VirtWifi is part of the virtual hardware, like a cable.
conf=/data/vendor/wifi/wpa_supplicant.conf
if ! wait_iface wlan0 20; then
    log "no wlan0"
else
    if [ ! -f $conf ]; then
        printf '%s\n' \
            "ctrl_interface=$sockets" \
            'update_config=1' \
            'network={' \
            '    ssid="VirtWifi"' \
            '    key_mgmt=NONE' \
            '}' > $conf
        log "$conf written with the open network VirtWifi"
    fi
    # IPv6 on wlan0 for Matter (the SDV core switches it off for every interface)
    echo 0 > /proc/sys/net/ipv6/conf/wlan0/disable_ipv6
    # the supplicant reads the config as wifi
    chown wifi:wifi $conf
    chmod 0660 $conf
    # the Wi-Fi bundle keeps the networks it joins (SAVE_CONFIG needs this)
    if [ "$(grep '^update_config=' $conf)" != update_config=1 ]; then
        # exactly one such line: the last one wins, so a later update_config=0 has to go
        sed -i '/^update_config=/d' $conf
        # a file that does not end with a newline would get the new line glued to its last one
        [ -n "$(tail -c1 $conf)" ] && echo >> $conf
        echo 'update_config=1' >> $conf || log "cannot write update_config=1 to $conf"
    fi
    # -g: the global control interface for the Wi-Fi bundle; -O stays for wpa_cli and the watchdog
    /vendor/bin/hw/wpa_supplicant -Dnl80211 -iwlan0 -c$conf -O$sockets -g@abstract:wpa_everyware &
    log "wpa_supplicant started"
    wifi_watchdog &
fi

wait
