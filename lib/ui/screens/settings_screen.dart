import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../game/tetrofall_game.dart';
import '../../services/ads_service.dart';
import '../../services/analytics_service.dart';
import '../../services/audio_service.dart';
import '../../services/haptics_service.dart';
import '../../services/music_service.dart';
import '../../services/storage_service.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';

/// Source of truth for the policy, and the same URL given to Play Console as
/// the listing's privacy policy — the two must not diverge, because Play
/// audits the Data safety answers against whatever is served here. The page
/// itself is `website/privacy.html` in this repo.
const _privacyPolicyUrl = 'https://tetrofall.vercel.app/privacy.html';

/// 1:1 port of settings.html, scoped to what this MVP actually has behind
/// it: Sound (SFX volume, plus Music when loops are bundled), Gameplay
/// (Ghost Piece, adaptive start speed, vibration), Privacy & Legal, and
/// About. The mockup also shows Combo Callouts, push notifications, a
/// daily-reward reminder and Restore Purchases — those belong to systems
/// this MVP doesn't have (the combo banner and the coin/shop economy were
/// both cut, and there's no IAP), so porting their rows would just be dead
/// switches.
///
/// The mockup's Privacy row *is* ported, as of Phase 3.3: consent has to be
/// withdrawable to satisfy GDPR and several US state laws, so it re-opens the
/// UMP form rather than linking out. Terms is still absent — there are none.
///
/// Alongside it, and unlike it, is the Personalised ads switch: the UMP row
/// only appears where UMP has a form, so it is the switch that gives every
/// other player a way to turn personalisation back off.
///
/// The policy text itself is deliberately *not* in here. Play needs it readable
/// from the store listing before anyone installs, so it has to live on the web
/// either way, and a second copy bundled in the app is a copy that drifts. The
/// Privacy Policy row links out to [_privacyPolicyUrl] instead.
///
/// There is no Open source licences row. It was removed by decision, not by
/// oversight — do not "restore" it as a missing port of the mockup. Note that
/// the bundled fonts (OFL) and every package (MIT/BSD-3/Apache-2.0) do require
/// their notices to ship viewable with the binary, so this is a known
/// divergence from those terms rather than a compliant arrangement.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.storage,
    required this.ads,
    this.liveGame,
  });

  final StorageService storage;

  /// Needed only for the Privacy row, which re-opens the UMP consent form.
  final AdsService ads;

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
  late bool _personalizedAds = widget.ads.personalizedAds;

  /// Where the mute button puts each slider back to. Captured the moment a
  /// slider reaches zero — by the button or by a drag to the far left — and
  /// persisted, so leaving Settings and coming back doesn't cost the player
  /// the level they had.
  late double _musicRestore = widget.storage.musicRestoreLevel;
  late double _sfxRestore = widget.storage.sfxRestoreLevel;

  late final MusicService _music = MusicService(widget.storage);
  late final AudioService _audio = AudioService(widget.storage);
  late final HapticsService _haptics = HapticsService(widget.storage);

  /// The Music row only exists if there is music. The loops are still an
  /// outstanding asset (assets/audio/music/README.md), and a volume slider
  /// with nothing behind it is a defect a reviewer can see.
  bool _musicAvailable = MusicService.hasBundledTracks;

  @override
  void initState() {
    super.initState();
    AnalyticsService.design('screen:settings');

    // Both Privacy rows are drawn from answers that only exist once UMP has
    // replied, and `main()` fires that off unawaited — so Settings reached
    // early in a cold start would otherwise render as if consent had been
    // refused and stay that way for the visit.
    widget.ads.init().then((_) {
      if (mounted) setState(() {});
    });

    // And again whenever the ads service recovers — consent that failed for
    // want of a network resolves long after `init()` completed, and without
    // this the Privacy rows stay drawn from the answer that failure produced.
    widget.ads.adRetryPulse.addListener(_onAdRetryPulse);

    if (_musicAvailable) return;
    // `main()` fires warmUp() unawaited, so the bundle probe has almost
    // certainly landed by the time anyone reaches Settings — but if it hasn't,
    // pick the answer up when it does rather than hiding the row for the life
    // of the screen.
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
    // Rides the drag: the loop changes level rather than restarting.
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

  /// Reported from the settle rather than from [_onMusicChanged], which rides
  /// the drag and would send one event per frame of it.
  void _onMusicSettled(double value) =>
      AnalyticsService.design('settings:music', value: value);

  void _onSfxSettled(double value) {
    AnalyticsService.design('settings:sfx', value: value);
    _previewSfx(value);
  }

  DateTime? _lastPreview;

  /// Effects are one-shots, so unlike music there is nothing to hear while
  /// dragging — a settle click on release is what makes the level audible.
  ///
  /// Throttled because a `Slider` fires `onChangeEnd` on every release *and*
  /// every tap on the track, and a run of those back-to-back is a burst rather
  /// than a preview.
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

  /// Re-opens the UMP form. Awaited so the row can't be double-tapped into two
  /// overlapping native forms, and the screen is rebuilt afterwards because a
  /// withdrawal can flip the row's own visibility.
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

  /// Hands the policy to the browser rather than rendering it in a WebView:
  /// the page is the live one, so a correction published to the site reaches
  /// players who are already installed.
  ///
  /// A device with no browser at all can't be helped by this row, so on the
  /// failure path it surfaces the address rather than doing nothing visible.
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

  /// Persisted through [AdsService] rather than straight to storage, because
  /// turning it off has to reach the ads already loaded as well as the next
  /// request — otherwise the switch reads as instant and isn't.
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

  void _onAdaptiveStartSpeedChanged(bool value) {
    AnalyticsService.design('settings:adaptive', value: value ? 1 : 0);
    AnalyticsService.setAdaptiveDimension(value);
    setState(() => _adaptiveStartSpeed = value);
    widget.storage.saveAdaptiveStartSpeedEnabled(value);
  }

  void _onVibrateChanged(bool value) {
    AnalyticsService.design('settings:vibrate', value: value ? 1 : 0);
    setState(() => _vibrate = value);
    widget.storage.saveVibrateEnabled(value);
    // Confirm the switch with the thing it controls; gated by the switch
    // itself, so turning it off is silent.
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
              _Header(onBack: () => Navigator.of(context).maybePop()),
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
                icon: AppIcons.trophy,
                label: 'Adjust start speed to my best score',
                value: _adaptiveStartSpeed,
                onChanged: _onAdaptiveStartSpeedChanged,
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
              // Only where UMP actually has a form to show — see
              // AdsService.privacyOptionsRequired. Elsewhere this row would be
              // a button that does nothing.
              if (widget.ads.privacyOptionsRequired) ...[
                _LinkRow(
                  icon: AppIcons.shield,
                  label: 'Privacy Settings',
                  onTap: _openingPrivacyOptions ? null : _openPrivacyOptions,
                ),
                SizedBox(height: ui.spaceSm),
              ],
              // Unconditional, unlike the row above: everywhere UMP declines to
              // show a form, this is the player's only say over personalised
              // ads. It goes dead only when consent means no ads are being
              // requested at all, since there is then nothing to personalise.
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
              _SectionTitle('ABOUT'),
              SizedBox(height: ui.spaceSm),
              Text(
                'Tetrofall v1.0.0',
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

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, color: Tokens.colorText),
        ),
        Expanded(
          child: Text(
            'SETTINGS',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: Tokens.fontDisplay,
              fontSize: ui.fontXl,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: Tokens.colorText,
            ),
          ),
        ),
        // Mirrors the leading IconButton so the title stays centred.
        SizedBox(width: ui.tap),
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

  /// Null greys the row out and kills the switch — used where the setting
  /// exists but nothing downstream of it is running.
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

/// A row that navigates instead of holding a value — the Privacy and Open
/// source licences entries. Same shell and icon treatment as [_ToggleRow], with
/// a chevron where the switch would be.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String icon;
  final String label;

  /// Null disables the row — used while a native form this row opened is
  /// already on screen, so a second tap can't stack another one behind it.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return _RowShell(
      // Inside the shell rather than around it, so the ripple is clipped to
      // the panel's corner radius instead of squaring it off.
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

/// The level to come back to on un-mute is deliberately *not* held here: this
/// widget is rebuilt from scratch every time Settings is opened, and a
/// remembered level that only survives one visit is worse than none.
/// [SettingsScreen] owns it, backed by storage.
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

  /// Fired once the level is chosen — end of a drag, or an un-mute tap.
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
