import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../ui/theme/app_icons.dart';
import '../../ui/theme/tokens.dart';
import '../tetrofall_game.dart';

/// Top bar overlay per `gameplay.html`: coin counter left, score + best
/// centre, pause slot right (R3). A minimal stand-in for the full Phase 10
/// port of the gameplay screen — this only needs to actually show the
/// numbers the engine already tracks.
///
/// Pushes updates from [Scoring]'s listener list instead of polling on a
/// timer (unlike the deleted debug overlay), so it only rebuilds when
/// score or coins actually change. Best score is in-memory only until
/// Phase 11's `StorageService`.
class ScoreHud extends StatefulWidget {
  const ScoreHud({super.key, required this.game});

  final TetrofallGame game;

  @override
  State<ScoreHud> createState() => _ScoreHudState();
}

class _ScoreHudState extends State<ScoreHud> {
  int _best = 0;

  @override
  void initState() {
    super.initState();
    widget.game.engine.scoring.addListener(_onScoringChanged);
  }

  @override
  void dispose() {
    widget.game.engine.scoring.removeListener(_onScoringChanged);
    super.dispose();
  }

  void _onScoringChanged() {
    final score = widget.game.engine.scoring.score;
    setState(() {
      if (score > _best) _best = score;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scoring = widget.game.engine.scoring;
    if (scoring.score > _best) _best = scoring.score;

    // A flow widget, not a `Positioned` overlay — its real height is
    // measured by the enclosing `Column` (R4's layout budget), and
    // everything else (the board, the booster panel) sizes off what's
    // actually left over instead of guessing a fixed offset.
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.spaceMd,
          vertical: Tokens.spaceSm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _CoinPill(coins: scoring.coins),
              ),
            ),
            _ScoreBlock(score: scoring.score, best: _best),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: _PauseButton(game: widget.game),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoinPill extends StatelessWidget {
  const _CoinPill({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Tokens.colorPanel,
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
        border: Border.all(color: Tokens.colorPanelBorder),
        boxShadow: const [Tokens.shadowSoft],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(AppIcons.coin, width: 22, height: 22),
          const SizedBox(width: Tokens.spaceSm),
          Text(
            '$coins',
            style: const TextStyle(
              fontFamily: Tokens.fontDisplay,
              fontSize: Tokens.fontSizeMd,
              fontWeight: FontWeight.bold,
              color: Tokens.colorText,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreBlock extends StatelessWidget {
  const _ScoreBlock({required this.score, required this.best});

  final int score;
  final int best;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$score',
          style: const TextStyle(
            fontFamily: Tokens.fontDisplay,
            fontSize: Tokens.fontSizeXl,
            fontWeight: FontWeight.w800,
            color: Tokens.colorText,
            height: 1.1,
          ),
        ),
        Text(
          'BEST $best',
          style: const TextStyle(
            fontSize: Tokens.fontSizeXs,
            fontWeight: FontWeight.bold,
            color: Tokens.colorTextMuted,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _PauseButton extends StatefulWidget {
  const _PauseButton({required this.game});

  final TetrofallGame game;

  @override
  State<_PauseButton> createState() => _PauseButtonState();
}

class _PauseButtonState extends State<_PauseButton> {
  @override
  Widget build(BuildContext context) {
    final paused = widget.game.paused;
    return GestureDetector(
      onTap: () => setState(() {
        if (paused) {
          widget.game.resumeEngine();
        } else {
          widget.game.pauseEngine();
        }
      }),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Tokens.colorPanel,
          shape: BoxShape.circle,
          border: Border.all(color: Tokens.colorPanelBorder),
          boxShadow: const [Tokens.shadowSoft],
        ),
        child: Center(
          child: paused
              ? const Icon(Icons.play_arrow, color: Tokens.colorText, size: 20)
              : SvgPicture.asset(
                  AppIcons.pause,
                  width: 18,
                  height: 18,
                  colorFilter: const ColorFilter.mode(
                    Tokens.colorText,
                    BlendMode.srcIn,
                  ),
                ),
        ),
      ),
    );
  }
}
