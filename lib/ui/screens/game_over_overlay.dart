import 'package:flutter/material.dart';

import '../../game/engine/events.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';
import '../widgets/icon_button.dart';
import '../widgets/modal_overlay.dart';
import '../widgets/primary_button.dart';

class GameOverOverlay extends StatelessWidget {
  const GameOverOverlay({
    super.key,
    required this.reason,
    required this.score,
    required this.best,
    required this.onRestart,
    required this.onHome,
    required this.canContinueWithAd,
    required this.onContinueWithAd,
    this.continueAdReady = true,
    this.onTooHard,
  });

  final GameOverReason reason;
  final int score;

  /// The best before this run; storage already holds this run's score.
  final int best;
  final VoidCallback onRestart;
  final VoidCallback onHome;

  final bool canContinueWithAd;
  final VoidCallback onContinueWithAd;
  final bool continueAdReady;

  /// Set after several quick deaths: offers "Too hard? Tell us".
  final VoidCallback? onTooHard;

  bool get _isNewBest => score > best;

  String get _reasonLabel => switch (reason) {
    GameOverReason.topOut => 'The rising floor reached the top.',
    GameOverReason.blockOut => 'No room left to spawn the next piece.',
  };

  /// What this run beat, or how close it came.
  Widget _bestLine(UiScale ui) {
    final muted = TextStyle(fontSize: ui.fontSm, color: Tokens.colorTextMuted);
    const strong = TextStyle(
      fontWeight: FontWeight.bold,
      color: Tokens.colorText,
    );
    if (_isNewBest) {
      if (best <= 0) return const SizedBox.shrink();
      return Text.rich(
        TextSpan(
          text: 'Previous best: ',
          style: muted,
          children: [TextSpan(text: '$best', style: strong)],
        ),
      );
    }
    return Text.rich(
      TextSpan(
        style: muted,
        children: [
          TextSpan(text: '${best - score}', style: strong),
          const TextSpan(text: ' from your best of '),
          TextSpan(text: '$best', style: strong),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return ModalOverlay(
      scrimOpacity: 0.72,
      // Only the button column below is panel-width.
      constrainWidth: false,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: ui.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isNewBest) ...[
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ui.px(14),
                  vertical: ui.px(5),
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(UiScale.radiusPill),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Tokens.colorGold, Color(0xFFD99A1F)],
                  ),
                  boxShadow: const [Tokens.shadowSoft],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star,
                      size: ui.px(13),
                      color: Tokens.colorWoodDark,
                    ),
                    SizedBox(width: ui.px(6)),
                    Text(
                      'NEW BEST!',
                      style: TextStyle(
                        fontFamily: Tokens.fontDisplay,
                        fontSize: ui.fontXs,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: Tokens.colorWoodDark,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: ui.spaceXs),
            ],
            Text(
              'GAME OVER',
              style: TextStyle(
                fontFamily: Tokens.fontDisplay,
                fontSize: ui.fontSm,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: Tokens.colorTextMuted,
              ),
            ),
            SizedBox(height: ui.spaceXs),
            Text(
              _reasonLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ui.fontSm,
                color: Tokens.colorTextMuted,
              ),
            ),
            SizedBox(height: ui.spaceMd),
            Text(
              'SCORE',
              style: TextStyle(
                fontSize: ui.fontSm,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
                color: Tokens.colorTextMuted,
              ),
            ),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFFE9B0),
                  Tokens.colorGold,
                  Color(0xFFC9821A),
                ],
                stops: [0, 0.55, 1],
              ).createShader(bounds),
              child: Text(
                '$score',
                style: TextStyle(
                  fontFamily: Tokens.fontDisplay,
                  fontSize: ui.fontHero,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
            ),
            _bestLine(ui),
            SizedBox(height: ui.spaceXl),
            SizedBox(
              width: ui.panelWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (canContinueWithAd) ...[
                    PrimaryButton(
                      label: continueAdReady
                          ? 'Watch Ad to Continue'
                          : 'Loading Ad…',
                      icon: Icon(
                        Icons.smart_display_outlined,
                        size: ui.iconSm,
                        color: Tokens.colorWoodDark,
                      ),
                      onPressed: continueAdReady ? onContinueWithAd : null,
                    ),
                    SizedBox(height: ui.spaceMd),
                    SecondaryButton(label: 'Play Again', onPressed: onRestart),
                  ] else
                    PrimaryButton(label: 'Play Again', onPressed: onRestart),
                  SizedBox(height: ui.spaceMd),
                  Center(
                    child: CircleIconButton(
                      tooltip: 'Home',
                      icon: const Icon(
                        Icons.home_outlined,
                        color: Tokens.colorText,
                      ),
                      onPressed: onHome,
                    ),
                  ),
                  if (onTooHard != null) _TooHardLink(onTap: onTooHard!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A quiet, dismissible nudge for someone who keeps dying early.
class _TooHardLink extends StatefulWidget {
  const _TooHardLink({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_TooHardLink> createState() => _TooHardLinkState();
}

class _TooHardLinkState extends State<_TooHardLink> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final ui = context.scale;
    final style = TextStyle(
      fontSize: ui.fontSm,
      color: Tokens.colorTextMuted,
      decoration: TextDecoration.underline,
      decorationColor: Tokens.colorTextMuted,
    );
    return Padding(
      padding: EdgeInsets.only(top: ui.spaceSm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: ui.spaceXs),
              child: Text('Too hard? Tell us', style: style),
            ),
          ),
          SizedBox(width: ui.spaceSm),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _dismissed = true),
            child: Padding(
              padding: EdgeInsets.all(ui.spaceXs),
              child: Icon(
                Icons.close,
                size: ui.iconSm,
                color: Tokens.colorTextMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
