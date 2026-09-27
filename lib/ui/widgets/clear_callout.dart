import 'package:flutter/material.dart';

import '../../game/engine/events.dart';
import '../../game/tetrofall_game.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';

/// "DOUBLE!" / "TRIPLE!" / "TETROFALL!" / "CHAIN x3" popups over the board,
/// for clears the player actually earned. Purely decorative: nothing here
/// feeds scoring, which has already happened by the time these fire.
class ClearCallout extends StatefulWidget {
  const ClearCallout({super.key, required this.game});

  final TetrofallGame game;

  @override
  State<ClearCallout> createState() => _ClearCalloutState();
}

class _ClearCalloutState extends State<ClearCallout> {
  /// Lines from the [RowsClearedEvent] just seen, consumed by the
  /// [ChainAdvancedEvent] that always follows a real (non-forced) clear.
  int? _pendingLines;

  final List<_CalloutItem> _items = [];
  int _nextId = 0;

  @override
  void initState() {
    super.initState();
    widget.game.engine.addEventListener(_onEvent);
  }

  @override
  void dispose() {
    widget.game.engine.removeEventListener(_onEvent);
    super.dispose();
  }

  void _onEvent(GameEvent event) {
    if (event is RowsClearedEvent) {
      // The continue sweep clears one forced row at a time and never emits
      // ChainAdvancedEvent, so it just never picks this back up.
      _pendingLines = event.forced ? null : event.rows.length;
      return;
    }
    if (event is ChainAdvancedEvent) {
      final lines = _pendingLines;
      _pendingLines = null;
      if (lines == null) return;
      final label = _labelFor(lines: lines, chainIndex: event.chainIndex);
      if (label == null) return;
      final id = _nextId++;
      setState(
        () => _items.add(
          _CalloutItem(
            id: id,
            text: label,
            big: lines >= 4 || event.chainIndex >= 2,
            stack: _items.length,
          ),
        ),
      );
    }
  }

  /// Null keeps the common single, unchained line clear quiet.
  String? _labelFor({required int lines, required int chainIndex}) {
    final lineWord = switch (lines) {
      1 => null,
      2 => 'DOUBLE!',
      3 => 'TRIPLE!',
      _ => 'TETROFALL!',
    };
    final chainLength = chainIndex + 1;
    if (chainLength <= 1) return lineWord;
    final chainWord = 'CHAIN x$chainLength';
    return lineWord == null ? chainWord : '$lineWord $chainWord';
  }

  void _remove(int id) {
    if (!mounted) return;
    setState(() => _items.removeWhere((item) => item.id == id));
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (final item in _items)
              _CalloutPop(
                key: ValueKey(item.id),
                item: item,
                onDone: () => _remove(item.id),
              ),
          ],
        ),
      ),
    );
  }
}

class _CalloutItem {
  const _CalloutItem({
    required this.id,
    required this.text,
    required this.big,
    required this.stack,
  });

  final int id;
  final String text;

  /// Tetrofalls and deeper chains earn the larger, gold treatment.
  final bool big;

  /// How many callouts were already showing when this one spawned, so a fast
  /// chain climbs upward instead of stacking flat on top of itself.
  final int stack;
}

class _CalloutPop extends StatefulWidget {
  const _CalloutPop({super.key, required this.item, required this.onDone});

  final _CalloutItem item;
  final VoidCallback onDone;

  @override
  State<_CalloutPop> createState() => _CalloutPopState();
}

class _CalloutPopState extends State<_CalloutPop>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 950);

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _duration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) widget.onDone();
        })
        ..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    final item = widget.item;
    final color = item.big ? Tokens.colorGold : Tokens.colorText;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        // Pop in with a slight overshoot, hold, then float up and fade.
        final scale = t < 0.12
            ? Curves.easeOut.transform(t / 0.12) * 0.7 + 0.5
            : t < 0.22
            ? 1.2 - Curves.easeIn.transform((t - 0.12) / 0.10) * 0.2
            : 1.0 +
                  Curves.easeIn.transform(((t - 0.65) / 0.35).clamp(0, 1)) *
                      0.08;
        final opacity = t < 0.65
            ? Curves.easeOut.transform((t / 0.12).clamp(0.0, 1.0))
            : 1.0 - Curves.easeIn.transform((t - 0.65) / 0.35);
        final riseFraction = Curves.easeOut.transform(t);

        return Transform.translate(
          offset: Offset(
            0,
            -item.stack * ui.spaceXl - riseFraction * ui.spaceXl * 1.5,
          ),
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: Text(
        item.text,
        style: TextStyle(
          fontFamily: Tokens.fontDisplay,
          fontWeight: FontWeight.w800,
          fontSize: item.big ? ui.fontXxl : ui.fontXl,
          color: color,
          letterSpacing: 0.5,
          shadows: const [
            Shadow(
              color: Color(0xCC1A0F08),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
            Shadow(color: Color(0x99000000), blurRadius: 14),
          ],
        ),
      ),
    );
  }
}
