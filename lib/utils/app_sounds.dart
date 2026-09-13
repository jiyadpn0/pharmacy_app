import 'package:flutter/services.dart';

class AppSounds {
  /// Plays the standard system alert/error sound.
  /// This uses the built-in OS sound (Windows/Android/macOS)
  /// so it is 100% royalty-free and safe.
  static void playError() {
    SystemSound.play(SystemSoundType.alert);
  }
}
