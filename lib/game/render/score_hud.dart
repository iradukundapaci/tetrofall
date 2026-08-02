import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/storage_service.dart';
import '../../ui/theme/app_icons.dart';
import '../../ui/theme/tokens.dart';
import '../tetrofall_game.dart';

class ScoreHud extends StatefulWidget {
  const ScoreHud({super.key, required this.game, required this.storage});

  final TetrofallGame game;
  final StorageService storage;

  @override
  State<ScoreHud> createState() => _ScoreHudState();
}

class _ScoreHudState extends State<ScoreHud> {
  late int _best = widget.storage.bestScore;

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
    final scoring = widget.game.engine.scoring;
    if (scoring.score > _best) {
      setState(() => _best = scoring.score);
      widget.storage.saveBestScore(_best);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scoring = widget.game.engine.scoring;
    if (scoring.score > _best) _best = scoring.score;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.spaceMd,
          vertical: Tokens.spaceSm,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _ScoreBlock(score: scoring.score, best: _best),
            _PauseButton(game: widget.game),
          ],
        ),
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

class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.game});

  final TetrofallGame game;

  @override
  Widget build(BuildContext context) {
    // Listens to the same notifier the pause overlay uses, so the icon
    // stays correct whether pause/resume is triggered from here or from
    // Resume in the overlay — not just from this button's own tap.
    return ValueListenableBuilder<bool>(
      valueListenable: game.pausedNotifier,
      builder: (context, paused, _) {
        return GestureDetector(
          onTap: () {
            if (paused) {
              game.resumeEngine();
            } else {
              game.pauseEngine();
            }
          },
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
                  ? const Icon(
                      Icons.play_arrow,
                      color: Tokens.colorText,
                      size: 20,
                    )
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
      },
    );
  }
}
