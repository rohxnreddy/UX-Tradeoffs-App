import 'package:flutter/services.dart';

class SpeakerControl {
  static const _channel = MethodChannel('com.bits.phonepathology/audio');

  static Future<void> enableSpeaker() async {
    try {
      await _channel.invokeMethod('setSpeakerOn');
    } catch (e) {
      // Silently fail on platforms that don't support this
    }
  }

  static Future<void> disableSpeaker() async {
    try {
      await _channel.invokeMethod('setSpeakerOff');
    } catch (e) {
      // Silently fail on platforms that don't support this
    }
  }
}
