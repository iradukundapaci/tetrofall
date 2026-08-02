import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Port of `.progress-bar` / `.progress-bar-fill` — a pill-shaped track
/// with a gold gradient fill, used by the splash loader.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    super.key,
    required this.value,
    this.height = 12,
    this.animationDuration = const Duration(milliseconds: 300),
    this.curve = Curves.easeOut,
  });

  /// 0.0–1.0
  final double value;
  final double height;
  final Duration animationDuration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0x59000000),
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
      ),
      clipBehavior: Clip.antiAlias,
      child: Align(
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: value.clamp(0.0, 1.0)),
          duration: animationDuration,
          curve: curve,
          builder: (context, animatedValue, child) => FractionallySizedBox(
            widthFactor: animatedValue,
            child: child,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Tokens.radiusPill),
              gradient: const LinearGradient(
                colors: [Tokens.colorGold, Color(0xFFFFD873)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
