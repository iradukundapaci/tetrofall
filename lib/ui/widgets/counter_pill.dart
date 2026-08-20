import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/ui_scale.dart';

/// Port of `.pill-counter` — an icon + label + value pill (BEST score,
/// coin counts, etc).
class CounterPill extends StatelessWidget {
  const CounterPill({
    super.key,
    required this.icon,
    required this.value,
    this.label,
  });

  final Widget icon;
  final String value;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ui.spaceMd,
        vertical: ui.spaceSm,
      ),
      decoration: BoxDecoration(
        color: Tokens.colorPanel,
        borderRadius: BorderRadius.circular(UiScale.radiusPill),
        border: Border.all(color: Tokens.colorPanelBorder),
        boxShadow: const [Tokens.shadowSoft],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null) ...[
            Text(
              label!,
              style: TextStyle(
                color: Tokens.colorTextMuted,
                fontSize: ui.fontXs,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
            SizedBox(width: ui.spaceSm),
          ],
          SizedBox(
            width: ui.px(Tokens.iconCounter),
            height: ui.px(Tokens.iconCounter),
            child: icon,
          ),
          SizedBox(width: ui.spaceSm),
          Text(
            value,
            style: TextStyle(
              fontFamily: Tokens.fontDisplay,
              fontSize: ui.fontMd,
              fontWeight: FontWeight.w700,
              color: Tokens.colorText,
            ),
          ),
        ],
      ),
    );
  }
}
