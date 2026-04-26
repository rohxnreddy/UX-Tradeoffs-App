// lib/src/services/speaker_control.dart
import 'package:flutter/services.dart';

class SpeakerControl {
  static const _channel = MethodChannel('com.bits.phonepathology/audio');

  static Future<void> enableSpeaker() async {
    try { await _channel.invokeMethod('setSpeakerOn'); } catch (_) {}
  }

  static Future<void> disableSpeaker() async {
    try { await _channel.invokeMethod('setSpeakerOff'); } catch (_) {}
  }
}
