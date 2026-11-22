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

# Lets firewalld pass the network of Cuttlefish instances. Run once, as root; the setting stays
# over reboots. Without firewalld there is nothing to do.
#
#     sudo device/cf-everyware/sdv_media_everyware_cf/tools/host-network.sh
#     sudo device/cf-everyware/sdv_media_everyware_cf/tools/host-network.sh --undo
#
# Cuttlefish's host service (cuttlefish-base) makes the bridges cvd-wbr (Wi-Fi) and cvd-ebr
# (Ethernet), with DHCP and DNS from dnsmasq and NAT to the default route. firewalld puts an
# interface of no zone into its default zone: that zone takes no DHCP from the instances, and
# nothing is forwarded from it into another zone, for example a VPN's tunnel that holds the
# default route. This script gives the bridges a zone of their own, "cuttlefish", that takes DHCP
# and DNS, and a policy that forwards from it to every zone. The NAT stays Cuttlefish's.

set -euo pipefail

ZONE=cuttlefish
POLICY=cuttlefish-out
BRIDGES=(cvd-wbr cvd-ebr)

[ "$(id -u)" = 0 ] || { echo "run as root: sudo $0 $*"; exit 1; }
if ! systemctl is-active -q firewalld; then
    echo "firewalld is not running: nothing to do"
    exit 0
fi

permanent() { firewall-cmd --permanent "$@" >/dev/null; }
has() { firewall-cmd --permanent "--get-$1" | tr ' ' '\n' | grep -qx "$2"; }

case "${1:-}" in
"")
    ;;
--undo)
    has policies "$POLICY" && permanent --delete-policy="$POLICY"
    has zones "$ZONE" && permanent --delete-zone="$ZONE"
    firewall-cmd --reload >/dev/null
    echo "removed the zone $ZONE and the policy $POLICY; the bridges are in the default zone again"
    exit 0
    ;;
*)
    echo "usage: $0 [--undo]"
    exit 1
    ;;
esac

has zones "$ZONE" || permanent --new-zone="$ZONE"
for bridge in "${BRIDGES[@]}"; do
    current="$(firewall-cmd --permanent --get-zone-of-interface="$bridge" 2>/dev/null || true)"
    [ "$current" = "$ZONE" ] && continue
    if [ -n "$current" ] && [ "$current" != "no zone" ]; then
        permanent --zone="$current" --remove-interface="$bridge"
    fi
    permanent --zone="$ZONE" --add-interface="$bridge"
done
permanent --zone="$ZONE" --add-service=dhcp --add-service=dns
has policies "$POLICY" || permanent --new-policy="$POLICY"
permanent --policy="$POLICY" --add-ingress-zone="$ZONE" --add-egress-zone=ANY
permanent --policy="$POLICY" --set-target=ACCEPT
firewall-cmd --reload >/dev/null

echo "zone $ZONE: ${BRIDGES[*]}, DHCP and DNS from the instances"
echo "policy $POLICY: $ZONE -> every zone, accepted"
echo "undo: sudo $0 --undo"
