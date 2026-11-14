/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// wlan_static: gives an interface the address, the default route and the DNS servers the host
// chose, where dhcpclient would get them from the host's DHCP server. For a host whose firewall
// drops DHCP on Cuttlefish's bridges: tools/run.sh (CF_STATIC_WIFI=1) puts the values on the
// kernel command line, as the host gives Cuttlefish's mobile network its static address.
// Publishes the gateway and the DNS servers as dhcpclient does (vendor.net.<iface>.gw,
// vendor.net.<iface>.dns1..4), which dnsproxyd and chronyd read.
//
//   wlan_static <interface> <address>/<prefix> <gateway> <dns> [<dns>...]

#include <arpa/inet.h>
#include <errno.h>
#include <net/if.h>
#include <net/route.h>
#include <netinet/in.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cstdlib>
#include <cstring>
#include <string>

#include <android-base/properties.h>
#include <android-base/unique_fd.h>
#include <log/log.h>

namespace {

constexpr int kMaxDns = 4;  // as dhcpclient

bool Ipv4(const char* text, sockaddr* out) {
    auto* in = reinterpret_cast<sockaddr_in*>(out);
    memset(in, 0, sizeof(*in));
    in->sin_family = AF_INET;
    return inet_pton(AF_INET, text, &in->sin_addr) == 1;
}

bool Fail(const char* what, const std::string& value) {
    ALOGE("%s %s: %s", what, value.c_str(), strerror(errno));
    return false;
}

bool Configure(const std::string& iface, const std::string& address, int prefix,
               const std::string& gateway) {
    android::base::unique_fd fd(socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0));
    if (fd < 0) return Fail("socket for", iface);

    ifreq ifr = {};
    strncpy(ifr.ifr_name, iface.c_str(), IFNAMSIZ - 1);
    if (!Ipv4(address.c_str(), &ifr.ifr_addr) || ioctl(fd, SIOCSIFADDR, &ifr) != 0) {
        return Fail("address", address);
    }
    auto* mask = reinterpret_cast<sockaddr_in*>(&ifr.ifr_netmask);
    memset(mask, 0, sizeof(*mask));
    mask->sin_family = AF_INET;
    mask->sin_addr.s_addr = prefix == 0 ? 0 : htonl(~0u << (32 - prefix));
    if (ioctl(fd, SIOCSIFNETMASK, &ifr) != 0) return Fail("netmask of", iface);
    if (ioctl(fd, SIOCGIFFLAGS, &ifr) != 0) return Fail("flags of", iface);
    ifr.ifr_flags |= IFF_UP;
    if (ioctl(fd, SIOCSIFFLAGS, &ifr) != 0) return Fail("up", iface);

    rtentry route = {};
    Ipv4("0.0.0.0", &route.rt_dst);
    Ipv4("0.0.0.0", &route.rt_genmask);
    if (!Ipv4(gateway.c_str(), &route.rt_gateway)) return Fail("gateway", gateway);
    route.rt_flags = RTF_UP | RTF_GATEWAY;
    std::string dev = iface;
    route.rt_dev = dev.data();
    // a reconnect finds the route of the last connect
    if (ioctl(fd, SIOCADDRT, &route) != 0 && errno != EEXIST) {
        return Fail("default route via", gateway);
    }
    return true;
}

}  // namespace

int main(int argc, char* argv[]) {
    if (argc < 5) {
        ALOGE("usage: %s <interface> <address>/<prefix> <gateway> <dns> [<dns>...]", argv[0]);
        return 1;
    }
    const std::string iface = argv[1];
    const std::string cidr = argv[2];
    const std::string gateway = argv[3];
    const size_t slash = cidr.find('/');
    const int prefix = slash == std::string::npos ? -1 : atoi(cidr.c_str() + slash + 1);
    if (prefix < 0 || prefix > 32) {
        ALOGE("not an address with a prefix: %s", cidr.c_str());
        return 1;
    }
    if (!Configure(iface, cidr.substr(0, slash), prefix, gateway)) return 1;

    android::base::SetProperty("vendor.net." + iface + ".gw", gateway);
    for (int n = 1; n <= kMaxDns; n++) {
        const char* dns = 3 + n < argc ? argv[3 + n] : "";
        android::base::SetProperty("vendor.net." + iface + ".dns" + std::to_string(n), dns);
    }
    ALOGI("%s: %s, gateway %s, %d DNS server(s), from the host", iface.c_str(), cidr.c_str(),
          gateway.c_str(), argc - 4);
    return 0;
}
