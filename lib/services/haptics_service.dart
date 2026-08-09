import 'package:flutter/services.dart' show HapticFeedback;

import 'storage_service.dart';

/// Every buzz goes through here so the Settings vibration switch is one
/// gate. The setting is read per call, so toggling it from the pause menu
/// lands on the next lock without anything being rebuilt.
class HapticsService {
  const HapticsService(this._storage);

  final StorageService _storage;

  bool get _enabled => _storage.vibrateEnabled;

  /// A piece locking into the stack.
  void light() {
    if (_enabled) HapticFeedback.lightImpact();
  }

  /// A row clearing.
  void medium() {
    if (_enabled) HapticFeedback.mediumImpact();
  }

  /// Column shifts and rotations.
  void selection() {
    if (_enabled) HapticFeedback.selectionClick();
  }
}
