import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';

class NetworkUtils {
  static Future<List<String>> getLocalIpAddresses() async {
    List<String> ipAddresses = [];

    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: true,
        type: InternetAddressType.IPv4,
      );

      // First look for hotspot interfaces
      for (var interface in interfaces) {
        if (interface.name.contains('ap0')) {
          for (var addr in interface.addresses) {
            if (!addr.address.startsWith('169.254')) {
              ipAddresses.add(addr.address);
              break;
            }
          }
        }
      }

      // Then look for WLAN interfaces
      final info = NetworkInfo();
      String? wifiIP = await info.getWifiIP();
      if (wifiIP != null && wifiIP.isNotEmpty && !ipAddresses.contains(wifiIP)) {
        ipAddresses.add(wifiIP);
      }

      // Add other WLAN interfaces
      for (var interface in interfaces) {
        if (interface.name.contains('wlan0') || interface.name.contains('en0')) {
          for (var addr in interface.addresses) {
            if (!addr.address.startsWith('169.254') &&
                !ipAddresses.contains(addr.address)) {
              ipAddresses.add(addr.address);
            }
          }
        }
      }
    } catch (e) {
      print('Error getting IP addresses: $e');
    }

    ipAddresses.sort((a, b) => isLikelyHotspotIP(a) ? -1 : 1);
    return ipAddresses;
  }

  static bool isLikelyHotspotIP(String ip) {
    return ip.startsWith('192.168.43.') ||
        ip.startsWith('172.20.10.') ||
        ip == '192.168.43.1' ||
        ip == '172.20.10.1';
  }
} 