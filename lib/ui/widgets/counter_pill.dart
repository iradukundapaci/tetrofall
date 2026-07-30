import 'package:flutter/material.dart';

import '../theme/tokens.dart';

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceMd, vertical: 8),
      decoration: BoxDecoration(
        color: Tokens.colorPanel,
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
        border: Border.all(color: Tokens.colorPanelBorder),
        boxShadow: const [Tokens.shadowSoft],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null) ...[
            Text(
              label!,
              style: const TextStyle(
                color: Tokens.colorTextMuted,
                fontSize: Tokens.fontSizeXs,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(width: Tokens.spaceSm),
          ],
          SizedBox(width: 22, height: 22, child: icon),
          const SizedBox(width: Tokens.spaceSm),
          Text(
            value,
            style: const TextStyle(
              fontFamily: Tokens.fontDisplay,
              fontSize: Tokens.fontSizeMd,
              fontWeight: FontWeight.w700,
              color: Tokens.colorText,
            ),
          ),
        ],
      ),
    );
  }
}
