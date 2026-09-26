import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/analytics_service.dart';
import '../../services/storage_service.dart';
import '../../ui/theme/app_icons.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/theme/ui_scale.dart';
import '../tetrofall_game.dart';
import 'next_piece_preview.dart';

class ScoreHud extends StatefulWidget {
  const ScoreHud({
    super.key,
    required this.game,
    required this.storage,
    this.recordsBest = true,
    this.showNextPiece = true,
  });

  final TetrofallGame game;
  final StorageService storage;

  /// False during the tutorial: coaching is not a run, and banking its rigged
  /// row would hand new players an unearned best and adaptive-start head start.
  final bool recordsBest;

  /// Off during the tutorial, which deals scripted pieces.
  final bool showNextPiece;

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
    if (widget.recordsBest && scoring.score > _best) {
      _best = scoring.score;
      widget.storage.saveBestScore(_best);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scoring = widget.game.engine.scoring;
    if (widget.recordsBest && scoring.score > _best) _best = scoring.score;

    final ui = context.scale;
    return SafeArea(
      bottom: false,
      // Fixed height, known before layout: `_GameplayBody` budgets the board
      // against it.
      child: SizedBox(
        height: ui.hudHeight,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ui.spaceMd,
            vertical: ui.spaceXs,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Shrinks rather than overflows at large system font sizes.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _ScoreBlock(score: scoring.score, best: _best),
                ),
              ),
              if (widget.showNextPiece)
                NextPiecePreview(engine: widget.game.engine),
              _PauseButton(game: widget.game),
            ],
          ),
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
    final ui = context.scale;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$score',
          style: TextStyle(
            fontFamily: Tokens.fontDisplay,
            fontSize: ui.fontXl,
            fontWeight: FontWeight.w800,
            color: Tokens.colorText,
            height: 1.1,
          ),
        ),
        Text(
          'BEST $best',
          style: TextStyle(
            fontSize: ui.fontXs,
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
    // Shares the pause overlay's notifier so the icon tracks either source.
    return ValueListenableBuilder<bool>(
      valueListenable: game.pausedNotifier,
      builder: (context, paused, _) {
        final ui = context.scale;
        return GestureDetector(
          onTap: () {
            // The quit prompt also pauses the engine but has its own event.
            AnalyticsService.design(paused ? 'pause:resume' : 'pause:open');
            if (paused) {
              game.resumeEngine();
            } else {
              game.pauseEngine();
            }
          },
          child: Container(
            width: ui.tap,
            height: ui.tap,
            decoration: BoxDecoration(
              color: Tokens.colorPanel,
              shape: BoxShape.circle,
              border: Border.all(color: Tokens.colorPanelBorder),
              boxShadow: const [Tokens.shadowSoft],
            ),
            child: Center(
              child: paused
                  ? Icon(
                      Icons.play_arrow,
                      color: Tokens.colorText,
                      size: ui.iconMd,
                    )
                  : SvgPicture.asset(
                      AppIcons.pause,
                      width: ui.iconSm,
                      height: ui.iconSm,
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
