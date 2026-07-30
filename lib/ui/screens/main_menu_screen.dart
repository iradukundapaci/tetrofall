import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/storage_service.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../widgets/counter_pill.dart';
import '../widgets/icon_button.dart';
import '../widgets/primary_button.dart';
import 'gameplay_screen.dart';
import 'settings_screen.dart';

/// 1:1 port of main-menu.html.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.colorBg,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: Tokens.bgWoodGradient),
        child: SafeArea(
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
                        // Video placeholder: a looping gameplay clip lands
                        // here later (main-menu.html's `.menu-video-slot`);
                        // empty until that asset exists.
                        const SizedBox(height: Tokens.spaceMd),
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
