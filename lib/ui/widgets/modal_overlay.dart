import 'package:flutter/material.dart';

import '../theme/ui_scale.dart';

/// Shared shell for every full-screen modal — pause, confirm-quit, game over,
/// and the tutorial's intro card.
///
/// Centres its child when there is room and scrolls it when there is not. The
/// scroll view is the load-bearing half: each of those overlays used to be a
/// bare `Center`, which on a short phone (or with the system font size raised)
/// silently overflowed rather than letting the player reach the buttons
/// underneath.
class ModalOverlay extends StatelessWidget {
  const ModalOverlay({
    super.key,
    required this.child,
    this.scrimOpacity = 0.5,
    this.constrainWidth = true,
  });

  final Widget child;
  final double scrimOpacity;

  /// False for game over, whose caption and score run the full viewport width
  /// and where only the button column is panel-width.
  final bool constrainWidth;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: ModalOverlayBody(
      scrimOpacity: scrimOpacity,
      constrainWidth: constrainWidth,
      child: child,
    ),
  );
}

/// [ModalOverlay] without the `Positioned.fill`, for the one caller that
/// already owns its own positioning — the tutorial overlay, whose coach mode
/// needs to stay a direct `Stack` child.
class ModalOverlayBody extends StatelessWidget {
  const ModalOverlayBody({
    super.key,
    required this.child,
    this.scrimOpacity = 0.5,
    this.constrainWidth = true,
  });

  final Widget child;
  final double scrimOpacity;
  final bool constrainWidth;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return ColoredBox(
      color: Colors.black.withValues(alpha: scrimOpacity),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.symmetric(vertical: ui.spaceMd),
            child: ConstrainedBox(
              // Minimum is the viewport, so `Center` still centres in the
              // common case and the scroll view only bites when the content
              // genuinely cannot fit.
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - ui.spaceMd * 2).clamp(
                  0.0,
                  double.infinity,
                ),
              ),
              child: Center(
                child: constrainWidth
                    ? SizedBox(width: ui.panelWidth, child: child)
                    : child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
