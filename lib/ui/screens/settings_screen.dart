import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../game/tetrofall_game.dart';
import '../../services/ads_service.dart';
import '../../services/analytics_service.dart';
import '../../services/audio_service.dart';
import '../../services/haptics_service.dart';
import '../../services/music_service.dart';
import '../../services/remote_flags.dart';
import '../../services/review_service.dart';
import '../../services/run_summary.dart';
import '../../services/storage_service.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';
import '../widgets/screen_header.dart';
import 'feedback_screen.dart';

/// Must match the privacy policy URL on the Play listing; the page is
/// `website/privacy.html`.
const _privacyPolicyUrl = 'https://tetrofall.vercel.app/privacy.html';

/// Sound, Gameplay, Privacy & Legal, Support and About. The Privacy row
/// re-opens the UMP form (consent must be withdrawable), which only exists in
/// some regions, so the Personalised ads switch gives everyone else a way to
/// turn personalisation off. There is deliberately no open-source licences
/// row.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.storage,
    required this.ads,
    this.liveGame,
  });

  final StorageService storage;

  final AdsService ads;

  /// The live game when opened from the pause overlay, so a Ghost Piece toggle
  /// applies immediately. Null from the main menu.
  final TetrofallGame? liveGame;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _musicVolume = widget.storage.musicVolume;
  late double _sfxVolume = widget.storage.sfxVolume;
  late bool _ghostPiece = widget.storage.ghostPieceEnabled;
  late bool _vibrate = widget.storage.vibrateEnabled;
  late bool _personalizedAds = widget.ads.personalizedAds;

  /// Where un-mute puts each slider back to, captured when it reaches zero and
  /// persisted.
  late double _musicRestore = widget.storage.musicRestoreLevel;
  late double _sfxRestore = widget.storage.sfxRestoreLevel;

  late final MusicService _music = MusicService(widget.storage);
  late final AudioService _audio = AudioService(widget.storage);
  late final HapticsService _haptics = HapticsService(widget.storage);

  /// The Music row only exists if loops are bundled.
  bool _musicAvailable = MusicService.hasBundledTracks;

  /// Read from the platform so About matches the installed build.
  String _version = '';

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {
      // No platform (tests, desktop): the line stays generic.
    }
  }

  /// Straight to the store page; unlike the in-app card it has no quota.
  Future<void> _rateUs() async {
    AnalyticsService.design('settings:rate');
    try {
      await InAppReviewService().openStoreListing();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open the store right now.")),
      );
    }
  }

  void _openFeedback() {
    AnalyticsService.design('settings:feedback');
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FeedbackScreen(lastRun: LastRun.summary),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    AnalyticsService.design('screen:settings');
    _loadVersion();

    // The Privacy rows depend on UMP's answer, which `main()` fires off
    // unawaited.
    widget.ads.init().then((_) {
      if (mounted) setState(() {});
    });

    // Consent that failed for want of a network resolves after `init()`.
    widget.ads.adRetryPulse.addListener(_onAdRetryPulse);

    if (_musicAvailable) return;
    // `main()` fires warmUp() unawaited; pick up the probe if it hasn't
    // landed yet.
    MusicService.warmUp().then((_) {
      if (mounted && MusicService.hasBundledTracks) {
        setState(() => _musicAvailable = true);
      }
    });
  }

  void _onAdRetryPulse() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.ads.adRetryPulse.removeListener(_onAdRetryPulse);
    super.dispose();
  }

  void _onMusicChanged(double value) {
    if (value == 0 && _musicVolume > 0) {
      _musicRestore = _musicVolume;
      widget.storage.saveMusicRestoreLevel(_musicVolume);
    }
    setState(() => _musicVolume = value);
    widget.storage.saveMusicVolume(value);
    // Rides the drag without restarting the loop.
    _music.setVolume(value);
  }

  void _onSfxChanged(double value) {
    if (value == 0 && _sfxVolume > 0) {
      _sfxRestore = _sfxVolume;
      widget.storage.saveSfxRestoreLevel(_sfxVolume);
    }
    setState(() => _sfxVolume = value);
    widget.storage.saveSfxVolume(value);
  }

  void _toggleMusicMute() {
    if (_musicVolume > 0) {
      _onMusicChanged(0);
      _onMusicSettled(0);
      return;
    }
    final restored = _musicRestore > 0 ? _musicRestore : 0.70;
    _onMusicChanged(restored);
    _onMusicSettled(restored);
  }

  void _toggleSfxMute() {
    if (_sfxVolume > 0) {
      _onSfxChanged(0);
      _onSfxSettled(0);
      return;
    }
    final restored = _sfxRestore > 0 ? _sfxRestore : 0.85;
    _onSfxChanged(restored);
    _onSfxSettled(restored);
  }

  /// Reported on settle, not from [_onMusicChanged], which fires every frame
  /// of a drag.
  void _onMusicSettled(double value) =>
      AnalyticsService.design('settings:music', value: value);

  void _onSfxSettled(double value) {
    AnalyticsService.design('settings:sfx', value: value);
    _previewSfx(value);
  }

  DateTime? _lastPreview;

  /// Effects are one-shots, so a click on release makes the level audible.
  /// Throttled because `onChangeEnd` fires on every release and track tap.
  void _previewSfx(double value) {
    final now = DateTime.now();
    final last = _lastPreview;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 150)) {
      return;
    }
    _lastPreview = now;
    _audio.play(Sfx.blockSettle, volumeOverride: value);
  }

  /// Guards against a double-tap stacking two native forms; the screen is
  /// rebuilt afterwards because a withdrawal can hide the row.
  bool _openingPrivacyOptions = false;

  Future<void> _openPrivacyOptions() async {
    if (_openingPrivacyOptions) return;
    AnalyticsService.design('settings:privacy_options');
    setState(() => _openingPrivacyOptions = true);
    try {
      await widget.ads.showPrivacyOptions();
    } finally {
      if (mounted) setState(() => _openingPrivacyOptions = false);
    }
  }

  /// Opens the live policy in the browser; with no browser, shows the address.
  Future<void> _openPrivacyPolicy() async {
    AnalyticsService.design('settings:privacy_policy');
    final launched = await launchUrl(
      Uri.parse(_privacyPolicyUrl),
      mode: LaunchMode.externalApplication,
    );
    if (launched || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Read the policy at $_privacyPolicyUrl')),
    );
  }

  /// Goes through [AdsService] so turning it off also reaches loaded ads.
  void _onPersonalizedAdsChanged(bool value) {
    AnalyticsService.design('settings:personalized_ads', value: value ? 1 : 0);
    setState(() => _personalizedAds = value);
    widget.ads.setPersonalizedAds(value);
  }

  void _onGhostPieceChanged(bool value) {
    AnalyticsService.design('settings:ghost', value: value ? 1 : 0);
    setState(() => _ghostPiece = value);
    widget.storage.saveGhostPieceEnabled(value);
    widget.liveGame?.showGhost = value;
  }

  void _onVibrateChanged(bool value) {
    AnalyticsService.design('settings:vibrate', value: value ? 1 : 0);
    setState(() => _vibrate = value);
    widget.storage.saveVibrateEnabled(value);
    // Confirms the switch; silent when turning it off.
    _haptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return Scaffold(
      backgroundColor: Tokens.colorBg,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: Tokens.bgWoodGradient),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: ui.spaceLg,
              vertical: ui.spaceMd,
            ),
            children: [
              ScreenHeader(
                title: 'SETTINGS',
                onBack: () => Navigator.of(context).maybePop(),
              ),
              SizedBox(height: ui.spaceLg),
              _SectionTitle('SOUND'),
              SizedBox(height: ui.spaceSm),
              if (_musicAvailable) ...[
                _VolumeRow(
                  icon: AppIcons.music,
                  label: 'Music',
                  value: _musicVolume,
                  onChanged: _onMusicChanged,
                  onSettled: _onMusicSettled,
                  onToggleMute: _toggleMusicMute,
                ),
                SizedBox(height: ui.spaceSm),
              ],
              _VolumeRow(
                icon: AppIcons.sound,
                label: 'Sound Effects',
                value: _sfxVolume,
                onChanged: _onSfxChanged,
                onSettled: _onSfxSettled,
                onToggleMute: _toggleSfxMute,
              ),
              SizedBox(height: ui.spaceLg),
              _SectionTitle('GAMEPLAY'),
              SizedBox(height: ui.spaceSm),
              _ToggleRow(
                icon: AppIcons.star,
                label: 'Ghost Piece',
                value: _ghostPiece,
                onChanged: _onGhostPieceChanged,
              ),
              SizedBox(height: ui.spaceSm),
              _ToggleRow(
                icon: AppIcons.vibrate,
                label: 'Vibration',
                value: _vibrate,
                onChanged: _onVibrateChanged,
              ),
              SizedBox(height: ui.spaceLg),
              _SectionTitle('PRIVACY & LEGAL'),
              SizedBox(height: ui.spaceSm),
              // Only where UMP has a form; see AdsService.privacyOptionsRequired.
              if (widget.ads.privacyOptionsRequired) ...[
                _LinkRow(
                  icon: AppIcons.shield,
                  label: 'Privacy Settings',
                  onTap: _openingPrivacyOptions ? null : _openPrivacyOptions,
                ),
                SizedBox(height: ui.spaceSm),
              ],
              // Always shown; goes dead only when no ads are requested.
              _ToggleRow(
                icon: AppIcons.message,
                label: 'Personalised ads',
                value: _personalizedAds && widget.ads.canRequestAds,
                onChanged: widget.ads.canRequestAds
                    ? _onPersonalizedAdsChanged
                    : null,
              ),
              SizedBox(height: ui.spaceSm),
              _LinkRow(
                icon: AppIcons.lock,
                label: 'Privacy Policy',
                onTap: _openPrivacyPolicy,
              ),
              SizedBox(height: ui.spaceLg),
              _SectionTitle('SUPPORT'),
              SizedBox(height: ui.spaceSm),
              _LinkRow(icon: AppIcons.star, label: 'Rate us', onTap: _rateUs),
              if (RemoteFlags.feedbackEnabled) ...[
                SizedBox(height: ui.spaceSm),
                _LinkRow(
                  icon: AppIcons.message,
                  label: 'Send feedback',
                  onTap: _openFeedback,
                ),
              ],
              SizedBox(height: ui.spaceLg),
              _SectionTitle('ABOUT'),
              SizedBox(height: ui.spaceSm),
              Text(
                _version.isEmpty ? 'Tetrofall' : 'Tetrofall v$_version',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: ui.fontXs,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: context.scale.fontXs,
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
    final ui = context.scale;
    return Container(
      padding: EdgeInsets.all(ui.spaceMd),
      decoration: BoxDecoration(
        color: Tokens.colorPanel,
        borderRadius: BorderRadius.circular(ui.radiusLg),
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

  /// Null greys the row out and disables the switch.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final color = onChanged == null ? Tokens.colorTextMuted : Tokens.colorText;
    final ui = context.scale;
    return _RowShell(
      child: Row(
        children: [
          SvgPicture.asset(
            icon,
            width: ui.iconMd,
            height: ui.iconMd,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
          SizedBox(width: ui.spaceMd),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: ui.fontSm,
                fontWeight: FontWeight.bold,
                color: color,
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

/// A row that navigates instead of holding a value: [_ToggleRow]'s shell with
/// a chevron where the switch would be.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String icon;
  final String label;

  /// Null disables the row, e.g. while its native form is already open.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return _RowShell(
      // Inside the shell so the ripple is clipped to its corner radius.
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ui.radiusLg),
        child: Row(
          children: [
            SvgPicture.asset(
              icon,
              width: ui.iconMd,
              height: ui.iconMd,
              colorFilter: ColorFilter.mode(
                onTap == null ? Tokens.colorTextMuted : Tokens.colorText,
                BlendMode.srcIn,
              ),
            ),
            SizedBox(width: ui.spaceMd),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: ui.fontSm,
                  fontWeight: FontWeight.bold,
                  color: onTap == null
                      ? Tokens.colorTextMuted
                      : Tokens.colorText,
                ),
              ),
            ),
            SvgPicture.asset(
              AppIcons.chevronRight,
              width: ui.iconSm,
              height: ui.iconSm,
              colorFilter: const ColorFilter.mode(
                Tokens.colorTextMuted,
                BlendMode.srcIn,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onToggleMute,
    this.onSettled,
  });

  final String icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback onToggleMute;

  /// Fired once the level is chosen: end of a drag, or an un-mute tap.
  final ValueChanged<double>? onSettled;

  bool get _muted => value == 0;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return _RowShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                icon,
                width: ui.iconMd,
                height: ui.iconMd,
                colorFilter: const ColorFilter.mode(
                  Tokens.colorText,
                  BlendMode.srcIn,
                ),
              ),
              SizedBox(width: ui.spaceMd),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: ui.fontSm,
                    fontWeight: FontWeight.bold,
                    color: Tokens.colorText,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onToggleMute,
                child: Container(
                  width: ui.tap,
                  height: ui.tap,
                  decoration: BoxDecoration(
                    color: _muted ? const Color(0x38D9432E) : Tokens.colorPanel,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _muted ? Tokens.colorRed : Tokens.colorPanelBorder,
                    ),
                  ),
                  child: Icon(
                    _muted ? Icons.volume_off : Icons.volume_up,
                    size: ui.iconSm,
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
              trackHeight: ui.px(Tokens.sliderTrackHeight),
            ),
            child: Slider(
              value: value,
              onChanged: onChanged,
              onChangeEnd: onSettled,
            ),
          ),
        ],
      ),
    );
  }
}
