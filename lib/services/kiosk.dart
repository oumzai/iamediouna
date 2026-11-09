import 'package:flutter/services.dart';

/// تثبيت الشاشة (Screen pinning) أثناء استعمال التلاميذ للتابلت،
/// حتى لا يخرجوا من التطبيق. يعتمد على MainActivity (انظر tool/android/MainActivity.kt).
class Kiosk {
  Kiosk._();

  static const _channel = MethodChannel('maktabati/kiosk');

  static Future<bool> start() async {
    try {
      return await _channel.invokeMethod<bool>('start') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> stop() async {
    try {
      return await _channel.invokeMethod<bool>('stop') ?? false;
    } catch (_) {
      return false;
    }
  }
}
