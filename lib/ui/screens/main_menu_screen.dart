import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:video_player/video_player.dart';

import '../../services/storage_service.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../widgets/counter_pill.dart';
import '../widgets/icon_button.dart';
import '../widgets/primary_button.dart';
import 'gameplay_screen.dart';
import 'settings_screen.dart';

/// 1:1 port of main-menu.html — main-menu.html's empty `.menu-video-slot`
/// becomes a full-bleed, muted, looping gameplay clip behind the whole
/// menu (not just the small reserved slot above PLAY), scrimmed for
/// readability.
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key, required this.storage});

  final StorageService storage;

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  // Mock purchase state only — IAP itself is Phase 11. Tapping just
  // flips the button, exactly like main-menu.html's script does; nothing
  // is persisted and nothing is actually hidden yet, since there is no ad
  // to remove.
  bool _adsRemoved = false;

  late final VideoPlayerController _videoController;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.asset(
      'assets/video/background.mp4',
    )
      ..setLooping(true)
      ..setVolume(0)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _videoController.play();
      });
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.colorBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(child: _BackgroundVideo(_videoController)),
          ),
          const Positioned.fill(child: _MenuScrim()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.spaceLg,
                Tokens.spaceLg,
                Tokens.spaceLg,
                Tokens.spaceXl,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CounterPill(
                        label: 'BEST',
                        value: _formatScore(widget.storage.bestScore),
                        icon: SvgPicture.asset(
                          AppIcons.trophy,
                          colorFilter: const ColorFilter.mode(
                            Tokens.colorGold,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                      CircleIconButton(
                        tooltip: 'Settings',
                        icon: SvgPicture.asset(
                          AppIcons.settings,
                          width: 20,
                          height: 20,
                          colorFilter: const ColorFilter.mode(
                            Tokens.colorText,
                            BlendMode.srcIn,
                          ),
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                SettingsScreen(storage: widget.storage),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 160,
                            child: PrimaryButton(
                              label: 'PLAY',
                              fontSize: Tokens.fontSizeMd,
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      GameplayScreen(storage: widget.storage),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: Tokens.spaceMd),
                          SizedBox(
                            width: 200,
                            child: SecondaryButton(
                              label: _adsRemoved
                                  ? 'Ads Removed'
                                  : 'No Ads — \$2.99',
                              highlighted: _adsRemoved,
                              icon: SvgPicture.asset(
                                _adsRemoved
                                    ? AppIcons.checkCircle
                                    : AppIcons.soundOff,
                                width: 18,
                                height: 18,
                                colorFilter: ColorFilter.mode(
                                  _adsRemoved
                                      ? Tokens.colorGold
                                      : Tokens.colorText,
                                  BlendMode.srcIn,
                                ),
                              ),
                              onPressed: _adsRemoved
                                  ? () {}
                                  : () => setState(() => _adsRemoved = true),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fills the available space with the video, cropping instead of
/// letterboxing (`BoxFit.cover`'s equivalent, since `VideoPlayer` itself
/// has no `fit` option). Falls back to the plain wood gradient until the
/// clip has decoded its first frame.
class _BackgroundVideo extends StatelessWidget {
  const _BackgroundVideo(this.controller);

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const DecoratedBox(
        decoration: BoxDecoration(gradient: Tokens.bgWoodGradient),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

/// Darkens the background video so the topbar and buttons on top of it
/// stay readable, lighter in the middle so the footage is still visible.
class _MenuScrim extends StatelessWidget {
  const _MenuScrim();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.6),
            Colors.black.withValues(alpha: 0.32),
            Colors.black.withValues(alpha: 0.65),
          ],
          stops: const [0, 0.5, 1],
        ),
      ),
    );
  }
}

String _formatScore(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
