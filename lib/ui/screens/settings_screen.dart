import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../game/tetrofall_game.dart';
import '../../services/audio_service.dart';
import '../../services/haptics_service.dart';
import '../../services/music_service.dart';
import '../../services/storage_service.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';

/// 1:1 port of settings.html, scoped to what this MVP actually has behind
/// it: Sound (music/SFX volume), Gameplay (Ghost Piece, adaptive start
/// speed, vibration), and About (version only). The mockup also shows
/// Combo Callouts, push notifications, a daily-reward reminder, and
/// Restore Purchases / Privacy / Terms links — those all belong to
/// systems this MVP doesn't have (the combo banner and the coin/shop
/// economy were both cut, and there's no IAP or legal copy yet), so
/// porting their rows here would just be dead switches.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.storage, this.liveGame});

  final StorageService storage;

  /// When Settings is opened from the pause overlay, the game underneath
  /// is still alive and should react immediately to a Ghost Piece toggle
  /// (game.md Phase 8 check #7). Null when opened from the main menu.
  final TetrofallGame? liveGame;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _musicVolume = widget.storage.musicVolume;
  late double _sfxVolume = widget.storage.sfxVolume;
  late bool _ghostPiece = widget.storage.ghostPieceEnabled;
  late bool _adaptiveStartSpeed = widget.storage.adaptiveStartSpeedEnabled;
  late bool _vibrate = widget.storage.vibrateEnabled;

  late final MusicService _music = MusicService(widget.storage);
  late final AudioService _audio = AudioService(widget.storage);
  late final HapticsService _haptics = HapticsService(widget.storage);

  void _onMusicChanged(double value) {
    setState(() => _musicVolume = value);
    widget.storage.saveMusicVolume(value);
    // Rides the drag: the loop changes level rather than restarting.
    _music.setVolume(value);
  }

  void _onSfxChanged(double value) {
    setState(() => _sfxVolume = value);
    widget.storage.saveSfxVolume(value);
  }

  /// Effects are one-shots, so unlike music there is nothing to hear while
  /// dragging — a settle click on release is what makes the level audible.
  void _previewSfx(double value) {
    _audio.play(Sfx.blockSettle, volumeOverride: value);
  }

  void _onGhostPieceChanged(bool value) {
    setState(() => _ghostPiece = value);
    widget.storage.saveGhostPieceEnabled(value);
    widget.liveGame?.showGhost = value;
  }

  void _onAdaptiveStartSpeedChanged(bool value) {
    setState(() => _adaptiveStartSpeed = value);
    widget.storage.saveAdaptiveStartSpeedEnabled(value);
  }

  void _onVibrateChanged(bool value) {
    setState(() => _vibrate = value);
    widget.storage.saveVibrateEnabled(value);
    // Confirm the switch with the thing it controls; gated by the switch
    // itself, so turning it off is silent.
    _haptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.colorBg,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: Tokens.bgWoodGradient),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: Tokens.spaceLg,
              vertical: Tokens.spaceMd,
            ),
            children: [
              _Header(onBack: () => Navigator.of(context).maybePop()),
              const SizedBox(height: Tokens.spaceLg),
              const _SectionTitle('SOUND'),
              const SizedBox(height: Tokens.spaceSm),
              _VolumeRow(
                icon: AppIcons.music,
                label: 'Music',
                value: _musicVolume,
                onChanged: _onMusicChanged,
              ),
              const SizedBox(height: Tokens.spaceSm),
              _VolumeRow(
                icon: AppIcons.sound,
                label: 'Sound Effects',
                value: _sfxVolume,
                onChanged: _onSfxChanged,
                onSettled: _previewSfx,
              ),
              const SizedBox(height: Tokens.spaceLg),
              const _SectionTitle('GAMEPLAY'),
              const SizedBox(height: Tokens.spaceSm),
              _ToggleRow(
                icon: AppIcons.star,
                label: 'Ghost Piece',
                value: _ghostPiece,
                onChanged: _onGhostPieceChanged,
              ),
              const SizedBox(height: Tokens.spaceSm),
              _ToggleRow(
                icon: AppIcons.trophy,
                label: 'Adjust start speed to my best score',
                value: _adaptiveStartSpeed,
                onChanged: _onAdaptiveStartSpeedChanged,
              ),
              const SizedBox(height: Tokens.spaceSm),
              _ToggleRow(
                icon: AppIcons.vibrate,
                label: 'Vibration',
                value: _vibrate,
                onChanged: _onVibrateChanged,
              ),
              const SizedBox(height: Tokens.spaceLg),
              const _SectionTitle('ABOUT'),
              const SizedBox(height: Tokens.spaceSm),
              const Text(
                'Tetrofall v1.0.0',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: Tokens.fontSizeXs,
                  color: Tokens.colorTextMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, color: Tokens.colorText),
        ),
        const Expanded(
          child: Text(
            'SETTINGS',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: Tokens.fontDisplay,
              fontSize: Tokens.fontSizeXl,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: Tokens.colorText,
            ),
          ),
        ),
        const SizedBox(width: 48),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: Tokens.fontSizeXs,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: Tokens.colorTextMuted,
      ),
    );
  }
}

class _RowShell extends StatelessWidget {
  const _RowShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      decoration: BoxDecoration(
        color: Tokens.colorPanel,
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        border: Border.all(color: Tokens.colorPanelBorder),
        boxShadow: const [Tokens.shadowSoft],
      ),
      child: child,
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      child: Row(
        children: [
          SvgPicture.asset(
            icon,
            width: 20,
            height: 20,
            colorFilter: const ColorFilter.mode(
              Tokens.colorText,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: Tokens.spaceMd),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: Tokens.fontSizeSm,
                fontWeight: FontWeight.bold,
                color: Tokens.colorText,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Tokens.colorGold,
            activeTrackColor: const Color(0x4DF2B632),
          ),
        ],
      ),
    );
  }
}

class _VolumeRow extends StatefulWidget {
  const _VolumeRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onSettled,
  });

  final String icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  /// Fired once the level is chosen — end of a drag, or an un-mute tap.
  final ValueChanged<double>? onSettled;

  @override
  State<_VolumeRow> createState() => _VolumeRowState();
}

class _VolumeRowState extends State<_VolumeRow> {
  double _lastNonZero = 0.7;

  bool get _muted => widget.value == 0;

  void _toggleMute() {
    if (_muted) {
      final restored = _lastNonZero > 0 ? _lastNonZero : 0.7;
      widget.onChanged(restored);
      widget.onSettled?.call(restored);
    } else {
      _lastNonZero = widget.value;
      widget.onChanged(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                widget.icon,
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(
                  Tokens.colorText,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: Tokens.spaceMd),
              Expanded(
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: Tokens.fontSizeSm,
                    fontWeight: FontWeight.bold,
                    color: Tokens.colorText,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _toggleMute,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _muted
                        ? const Color(0x38D9432E)
                        : Tokens.colorPanel,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _muted
                          ? Tokens.colorRed
                          : Tokens.colorPanelBorder,
                    ),
                  ),
                  child: Icon(
                    _muted ? Icons.volume_off : Icons.volume_up,
                    size: 18,
                    color: _muted ? Tokens.colorRed : Tokens.colorText,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Tokens.colorGold,
              inactiveTrackColor: const Color(0x59000000),
              thumbColor: Tokens.colorGold,
              overlayColor: const Color(0x33F2B632),
              trackHeight: 8,
            ),
            child: Slider(
              value: widget.value,
              onChanged: widget.onChanged,
              onChangeEnd: widget.onSettled,
            ),
          ),
        ],
      ),
    );
  }
}
