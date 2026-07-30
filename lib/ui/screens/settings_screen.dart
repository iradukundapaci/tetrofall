import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../services/storage_service.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';

/// The app's first Settings surface — currently just the adaptive
/// start-speed toggle, styled to match `screens/settings.html`'s
/// `.st-header`/`.st-section`/`.setting-row` layout (wood-dark background,
/// gold accents, a translucent panel row per setting).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.storage});

  final StorageService storage;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _adaptiveStartSpeed = widget.storage.adaptiveStartSpeedEnabled;

  void _onAdaptiveStartSpeedChanged(bool value) {
    setState(() => _adaptiveStartSpeed = value);
    widget.storage.saveAdaptiveStartSpeedEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.colorBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.spaceLg,
            vertical: Tokens.spaceMd,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(onBack: () => Navigator.of(context).maybePop()),
              const SizedBox(height: Tokens.spaceLg),
              const _SectionTitle('GAMEPLAY'),
              const SizedBox(height: Tokens.spaceSm),
              _SettingRow(
                icon: AppIcons.trophy,
                label: 'Adjust start speed to my best score',
                value: _adaptiveStartSpeed,
                onChanged: _onAdaptiveStartSpeedChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, color: Tokens.colorText),
        ),
        const Expanded(
          child: Text(
            'SETTINGS',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: Tokens.fontDisplay,
              fontSize: Tokens.fontSizeXl,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: Tokens.colorText,
            ),
          ),
        ),
        // Balances the back button's width so the title sits centered in
        // the row, not just centered in the leftover space.
        const SizedBox(width: 48),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: Tokens.fontSizeXs,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: Tokens.colorTextMuted,
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      decoration: BoxDecoration(
        color: Tokens.colorPanel,
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        border: Border.all(color: Tokens.colorPanelBorder),
        boxShadow: const [Tokens.shadowSoft],
      ),
      child: Row(
        children: [
          SvgPicture.asset(
            icon,
            width: 20,
            height: 20,
            colorFilter: const ColorFilter.mode(
              Tokens.colorText,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: Tokens.spaceMd),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: Tokens.fontSizeSm,
                fontWeight: FontWeight.bold,
                color: Tokens.colorText,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Tokens.colorGold,
            activeTrackColor: const Color(0x4DF2B632), // rgba(242,182,50,0.3)
          ),
        ],
      ),
    );
  }
}
