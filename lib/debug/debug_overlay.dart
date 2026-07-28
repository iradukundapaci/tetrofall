import 'dart:async';

import 'package:flutter/material.dart';

import '../game/engine/booster_engine.dart';
import '../game/engine/cell.dart';
import '../game/tetrofall_game.dart';
import '../ui/theme/tokens.dart';
import 'debug_flags.dart';

/// Live debug affordances layered on top of the actual rendered game, as
/// opposed to `DebugScreen`'s ASCII step-through view. These only make
/// sense against the real animation, so they live here — the Phase 4
/// rise-speed slider today, joined by Phase 5's time-scale slider, Phase
/// 6's live stats readout, Phase 7's block-type stamper, and Phase 8's
/// give-charges button as those phases land. Gated by
/// [DebugFlags.debugToolsEnabled]; stripped in Phase 12.
class DebugOverlay extends StatefulWidget {
  const DebugOverlay({super.key, required this.game});

  final TetrofallGame game;

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  bool _expanded = false;
  double _riseSpeed = 1.0;
  double _timeScale = 1.0;
  Timer? _refreshTimer;

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _setExpanded(bool value) {
    setState(() => _expanded = value);
    _refreshTimer?.cancel();
    if (value) {
      // The live readouts (Phase 6+) need to repaint even though nothing
      // in this widget tree is itself animated.
      _refreshTimer = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => setState(() {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!DebugFlags.debugToolsEnabled) return const SizedBox.shrink();

    return Positioned(
      left: 8,
      bottom: 8,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_expanded) _panel(),
            const SizedBox(height: 6),
            FloatingActionButton.small(
              heroTag: 'debug_overlay_toggle',
              onPressed: () => _setExpanded(!_expanded),
              child: Icon(_expanded ? Icons.close : Icons.bug_report),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel() {
    final engine = widget.game.engine;
    final rise = engine.riseController;
    return Container(
      width: 260,
      padding: const EdgeInsets.all(Tokens.spaceSm),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(Tokens.radiusSm),
        border: Border.all(color: Tokens.colorPanelBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _label('rise speed  ${_riseSpeed.toStringAsFixed(1)}x'),
          Slider(
            value: _riseSpeed,
            min: 0.5,
            max: 10.0,
            divisions: 19,
            onChanged: (v) => setState(() {
              _riseSpeed = v;
              rise.debugSpeedMultiplier = v;
            }),
          ),
          _label('time scale  ${_timeScale.toStringAsFixed(2)}x'),
          Slider(
            value: _timeScale,
            min: 0.1,
            max: 1.0,
            divisions: 18,
            onChanged: (v) => setState(() {
              _timeScale = v;
              widget.game.timeScale = v;
            }),
          ),
          const Divider(color: Tokens.colorPanelBorder),
          _label(
            'phase: ${engine.phase.name}   chain: ${engine.chainIndex}\n'
            'elapsed: ${rise.elapsed.toStringAsFixed(1)}s   '
            'drop: ${engine.pieceController.dropInterval.inMilliseconds}ms\n'
            'rise: ${rise.riseInterval.toStringAsFixed(1)}s   '
            'fill: ${(rise.fillRatio * 100).toStringAsFixed(0)}%\n'
            'score: ${engine.scoring.score}   coins: ${engine.scoring.coins}\n'
            'destroyed(resolve): ${engine.scoring.blocksDestroyedThisResolve}',
          ),
          const Divider(color: Tokens.colorPanelBorder),
          _label('stamp block (tap the board to place it):'),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final type in BlockType.values)
                if (type != BlockType.wood)
                  ChoiceChip(
                    label: Text(type.name, style: const TextStyle(fontSize: 10)),
                    selected: widget.game.debugStampType == type,
                    onSelected: (selected) => setState(() {
                      widget.game.debugStampType = selected ? type : null;
                    }),
                  ),
            ],
          ),
          const Divider(color: Tokens.colorPanelBorder),
          _label(
            'charges: '
            '${BoosterType.values.map((t) => '${t.name}=${engine.boosterEngine.charges[t]}').join('  ')}',
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ElevatedButton(
                onPressed: () =>
                    setState(() => engine.boosterEngine.debugGiveCharges(99)),
                child: const Text('Give 99 charges'),
              ),
              ElevatedButton(
                onPressed: () => setState(engine.useTimeFreeze),
                child: const Text('Use Time Freeze'),
              ),
              ElevatedButton(
                onPressed: () => setState(engine.useScoreMultiplier),
                child: const Text('Use Score x2'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text(
      text,
      style: const TextStyle(color: Tokens.colorText, fontSize: 11),
    ),
  );
}
