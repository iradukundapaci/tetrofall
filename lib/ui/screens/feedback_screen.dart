import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/feedback_service.dart';
import '../../services/run_summary.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';
import '../widgets/panel.dart';
import '../widgets/primary_button.dart';

/// "Send feedback": a short form for the players who are not about to leave a
/// good rating. Reached from Settings, and from the game-over screen after a
/// few quick deaths in a row (pre-filled with *too hard*).
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, this.initialCategory, this.lastRun});

  final FeedbackCategory? initialCategory;

  /// The run to attach when the player ticks "Include my last run". Null hides
  /// the toggle.
  final EndlessRunSummary? lastRun;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  late FeedbackCategory _category =
      widget.initialCategory ?? FeedbackCategory.idea;
  final _controller = TextEditingController();
  late bool _includeRun = widget.lastRun != null;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.design('screen:feedback');
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSend => !_sending && _controller.text.trim().isNotEmpty;

  Future<void> _send() async {
    setState(() => _sending = true);
    final ok = await FeedbackService.send(
      category: _category,
      text: _controller.text,
      lastRun: _includeRun ? widget.lastRun : null,
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Thanks — we read every message.')),
      );
      Navigator.of(context).pop();
    } else {
      // The text stays put so nothing typed is lost.
      setState(() => _sending = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't send right now. Check your connection and try again.",
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return Scaffold(
      backgroundColor: Tokens.colorBg,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: Tokens.bgWoodGradient),
        child: SafeArea(
          child: Column(
            children: [
              _Header(onBack: () => Navigator.of(context).pop()),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.all(ui.spaceMd),
                  children: [
                    AppPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label(ui, 'WHAT IS IT ABOUT?'),
                          SizedBox(height: ui.spaceSm),
                          Wrap(
                            spacing: ui.spaceSm,
                            runSpacing: ui.spaceSm,
                            children: [
                              for (final c in FeedbackCategory.values)
                                _CategoryChip(
                                  label: c.label,
                                  selected: c == _category,
                                  onTap: () => setState(() => _category = c),
                                ),
                            ],
                          ),
                          SizedBox(height: ui.spaceLg),
                          _label(ui, 'YOUR MESSAGE'),
                          SizedBox(height: ui.spaceSm),
                          TextField(
                            controller: _controller,
                            maxLength: FeedbackService.maxTextLength,
                            maxLines: 6,
                            minLines: 4,
                            textCapitalization: TextCapitalization.sentences,
                            style: TextStyle(
                              fontSize: ui.fontMd,
                              color: Tokens.colorText,
                            ),
                            cursorColor: Tokens.colorGold,
                            decoration: InputDecoration(
                              hintText: 'Tell us what happened…',
                              hintStyle: TextStyle(
                                color: Tokens.colorTextMuted,
                                fontSize: ui.fontMd,
                              ),
                              counterStyle: TextStyle(
                                color: Tokens.colorTextMuted,
                                fontSize: ui.fontXs,
                              ),
                              filled: true,
                              fillColor: Tokens.colorPanel,
                              enabledBorder: _border(
                                ui,
                                Tokens.colorPanelBorder,
                              ),
                              focusedBorder: _border(ui, Tokens.colorGold),
                            ),
                          ),
                          if (widget.lastRun != null) ...[
                            SizedBox(height: ui.spaceSm),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Include my last run',
                                    style: TextStyle(
                                      fontSize: ui.fontMd,
                                      color: Tokens.colorText,
                                    ),
                                  ),
                                ),
                                Switch(
                                  value: _includeRun,
                                  activeThumbColor: Tokens.colorGold,
                                  onChanged: (v) =>
                                      setState(() => _includeRun = v),
                                ),
                              ],
                            ),
                            Text(
                              'Score and length only — no personal details.',
                              style: TextStyle(
                                fontSize: ui.fontXs,
                                color: Tokens.colorTextMuted,
                              ),
                            ),
                          ],
                          SizedBox(height: ui.spaceLg),
                          PrimaryButton(
                            label: _sending ? 'Sending…' : 'Send',
                            onPressed: _canSend ? _send : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(UiScale ui, String text) => Text(
    text,
    style: TextStyle(
      fontSize: ui.fontXs,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.0,
      color: Tokens.colorTextMuted,
    ),
  );

  OutlineInputBorder _border(UiScale ui, Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(ui.radiusSm),
    borderSide: BorderSide(color: color),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, color: Tokens.colorText),
        ),
        Expanded(
          child: Text(
            'FEEDBACK',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: Tokens.fontDisplay,
              fontSize: ui.fontXl,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: Tokens.colorText,
            ),
          ),
        ),
        // Mirrors the leading IconButton so the title stays centred.
        SizedBox(width: ui.tap),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ui.spaceMd,
          vertical: ui.spaceSm,
        ),
        decoration: BoxDecoration(
          color: selected ? Tokens.colorGold : Tokens.colorPanel,
          borderRadius: BorderRadius.circular(UiScale.radiusPill),
          border: Border.all(
            color: selected ? Tokens.colorGold : Tokens.colorPanelBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: ui.fontSm,
            fontWeight: FontWeight.w700,
            color: selected ? Tokens.colorWoodDark : Tokens.colorText,
          ),
        ),
      ),
    );
  }
}
