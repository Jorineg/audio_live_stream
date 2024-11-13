import 'package:flutter/services.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class PlatformUtils {
  static const platform = MethodChannel('com.jorin.audio_live_stream/service');
  static const hostnameChannel = MethodChannel('com.jorin.audio_live_stream/hostname');

  static Future<void> startAndroidForegroundService() async {
    if (Platform.isAndroid) {
      try {
        await platform.invokeMethod('startAudioStreamingService');
      } on PlatformException catch (e) {
        print("Failed to start foreground service: '${e.message}'.");
      }
    }
  }

  static Future<void> stopAndroidForegroundService() async {
    if (Platform.isAndroid) {
      try {
        await platform.invokeMethod('stopAudioStreamingService');
      } on PlatformException catch (e) {
        print("Failed to stop foreground service: '${e.message}'.");
      }
    }
  }

  static Future<String> getDeviceName() async {
    if (Platform.isAndroid) {
      try {
        final deviceName = await hostnameChannel.invokeMethod('getHostName');
        return deviceName ?? 'audiostream';
      } on PlatformException catch (e) {
        print("Failed to get hostname: '${e.message}'.");
        return 'audiostream';
      }
    } else if (Platform.isIOS) {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      return iosInfo.name;
    }
    return 'audiostream';
  }
} 