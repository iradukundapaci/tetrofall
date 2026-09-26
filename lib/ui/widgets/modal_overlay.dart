import 'package:flutter/material.dart';

import '../theme/ui_scale.dart';

/// Shell for every full-screen modal: centres its child when there is room
/// and scrolls when there isn't, so buttons stay reachable on short phones or
/// large system fonts.
class ModalOverlay extends StatelessWidget {
  const ModalOverlay({
    super.key,
    required this.child,
    this.scrimOpacity = 0.5,
    this.constrainWidth = true,
  });

  final Widget child;
  final double scrimOpacity;

  /// False for game over, where only the button column is panel-width.
  final bool constrainWidth;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: scrimOpacity),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: EdgeInsets.symmetric(vertical: ui.spaceMd),
              child: ConstrainedBox(
                // Minimum is the viewport, so `Center` centres in the common
                // case and the scroll view only bites when content can't fit.
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
      ),
    );
  }
}
