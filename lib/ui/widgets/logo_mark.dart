import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The T-tetromino mark, built from wood-block cells at a given [cellSize];
/// pure code, no raster asset.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.cellSize = 40});

  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final gap = cellSize * 0.125;
    return SizedBox(
      width: cellSize * 3 + gap * 2,
      height: cellSize * 2 + gap,
      child: Stack(
        children: [
          // The top of the T.
          Positioned(
            left: cellSize + gap,
            top: 0,
            child: _LogoBlock(size: cellSize),
          ),
          // The crossbar.
          Positioned(left: 0, top: cellSize + gap, child: _LogoBlock(size: cellSize)),
          Positioned(
            left: cellSize + gap,
            top: cellSize + gap,
            child: _LogoBlock(size: cellSize),
          ),
          Positioned(
            left: (cellSize + gap) * 2,
            top: cellSize + gap,
            child: _LogoBlock(size: cellSize),
          ),
        ],
      ),
    );
  }
}

class _LogoBlock extends StatelessWidget {
  const _LogoBlock({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.2;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0x59000000)),
        gradient: const LinearGradient(
          begin: Alignment(-0.6, -1),
          end: Alignment(0.6, 1),
          colors: [
            Tokens.colorWoodLight,
            Tokens.colorWoodMid,
            Tokens.colorWoodDark,
          ],
          stops: [0, 0.55, 1],
        ),
        boxShadow: const [Tokens.shadowSoft],
      ),
      // BoxShadow has no inset variant, so an overlay gradient carves the
      // bevel.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.28),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.3),
            ],
            stops: const [0, 0.25, 0.7, 1],
          ),
        ),
      ),
    );
  }
}
