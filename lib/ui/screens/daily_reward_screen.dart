import 'package:flutter/material.dart';

import '../../game/config/economy_tuning.dart';
import '../../services/ads_service.dart';
import '../../services/analytics_service.dart';
import '../../services/daily_service.dart';
import '../../services/economy.dart';
import '../theme/tokens.dart';
import '../theme/ui_scale.dart';
import '../widgets/coin_balance_pill.dart';
import '../widgets/panel.dart';
import '../widgets/primary_button.dart';
import '../widgets/progress_bar.dart';
import '../widgets/purchase_prompt.dart';
import 'shop_screen.dart' show showChestReward;

/// Port of `screens/daily-reward.html`, plus today's challenges.
///
/// This is the zero-ad floor of the economy — what a player earns without
/// watching anything — so it has to be easy to find and quick to collect.
class DailyRewardScreen extends StatelessWidget {
  const DailyRewardScreen({
    super.key,
    required this.ads,
    required this.economy,
  });

  final AdsService ads;
  final Economy economy;

  DailyService get _daily => economy.daily;

  Future<void> _claimLogin(BuildContext context) async {
    final claimed = await _daily.claimLogin();
    if (claimed == null) return;
    AnalyticsService.design('daily:login');
    final (_, chest) = claimed;
    if (chest != null && context.mounted) await showChestReward(context, chest);
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return Scaffold(
      backgroundColor: Tokens.colorBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(ui.spaceMd),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: Tokens.colorText),
                  ),
                  Text('Daily', style: _title(ui)),
                  const Spacer(),
                  CoinBalancePill(
                    wallet: economy.wallet,
                    onTap: () => openCoinVault(
                      context,
                      ads: ads,
                      wallet: economy.wallet,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: _daily,
                builder: (context, _) => ListView(
                  padding: EdgeInsets.fromLTRB(
                    ui.spaceLg,
                    0,
                    ui.spaceLg,
                    ui.spaceXl,
                  ),
                  children: [
                    _calendar(context, ui),
                    SizedBox(height: ui.spaceLg),
                    Text(
                      "TODAY'S CHALLENGES",
                      style: TextStyle(
                        fontFamily: Tokens.fontBody,
                        fontSize: ui.fontXs,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Tokens.colorTextMuted,
                      ),
                    ),
                    SizedBox(height: ui.spaceSm),
                    for (final c in _daily.challenges) _challenge(ui, c),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _calendar(BuildContext context, UiScale ui) {
    final through = _daily.claimedThroughDay;
    final today = _daily.canClaimLogin ? _daily.nextLoginDay : null;
    return AppPanel(
      child: Column(
        children: [
          Text('Login Streak', style: _title(ui)),
          SizedBox(height: ui.spaceMd),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: ui.spaceSm,
            runSpacing: ui.spaceSm,
            children: [
              for (var day = 1; day <= 7; day++)
                _DayCell(
                  day: day,
                  reward: DailyService.rewardForDay(day),
                  claimed: day <= through,
                  isToday: day == today,
                ),
            ],
          ),
          SizedBox(height: ui.spaceMd),
          if (today != null)
            PrimaryButton(
              label: 'Claim day $today',
              onPressed: () => _claimLogin(context),
            )
          else
            Text(
              'Come back tomorrow for day ${_daily.nextLoginDay % 7 + 1}.',
              style: _body(ui, muted: true),
            ),
        ],
      ),
    );
  }

  Widget _challenge(UiScale ui, DailyChallenge c) => Padding(
    padding: EdgeInsets.only(bottom: ui.spaceSm),
    child: AppPanel(
      padding: EdgeInsets.all(ui.spaceMd),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.label,
                  style: _body(ui).copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: ui.spaceXs),
                AppProgressBar(value: c.progress / c.target),
                SizedBox(height: ui.spaceXs),
                Text(
                  '${c.progress} / ${c.target}',
                  style: _body(ui, muted: true).copyWith(fontSize: ui.fontXs),
                ),
              ],
            ),
          ),
          SizedBox(width: ui.spaceMd),
          if (c.claimed)
            const Icon(Icons.check_circle, color: Tokens.colorGreen)
          else
            TextButton(
              onPressed: c.complete
                  ? () async {
                      if (await _daily.claimChallenge(c)) {
                        AnalyticsService.design(
                          'daily:challenge:${c.kind.name}',
                        );
                      }
                    }
                  : null,
              child: Text(
                '+${EconomyTuning.dailyChallengeReward}',
                style: _body(ui).copyWith(
                  fontWeight: FontWeight.w800,
                  color: c.complete ? Tokens.colorGold : Tokens.colorTextMuted,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

TextStyle _title(UiScale ui) => TextStyle(
  fontFamily: Tokens.fontDisplay,
  fontSize: ui.fontLg,
  fontWeight: FontWeight.w700,
  color: Tokens.colorText,
);

TextStyle _body(UiScale ui, {bool muted = false}) => TextStyle(
  fontFamily: Tokens.fontBody,
  fontSize: ui.fontSm,
  color: muted ? Tokens.colorTextMuted : Tokens.colorText,
);

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.reward,
    required this.claimed,
    required this.isToday,
  });

  final int day;
  final LoginReward reward;
  final bool claimed;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final ui = context.scale;
    return Container(
      width: ui.px(72),
      padding: EdgeInsets.all(ui.spaceXs),
      decoration: BoxDecoration(
        color: isToday ? const Color(0x2EF2B632) : Tokens.colorPanel,
        borderRadius: BorderRadius.circular(ui.radiusSm),
        border: Border.all(
          color: isToday ? Tokens.colorGold : Tokens.colorPanelBorder,
        ),
      ),
      child: Column(
        children: [
          Text(
            'Day $day',
            style: _body(ui, muted: true).copyWith(fontSize: ui.fontXs),
          ),
          SizedBox(height: ui.spaceXs),
          if (claimed)
            Icon(Icons.check_circle, color: Tokens.colorGreen, size: ui.iconMd)
          else
            Text(
              reward.label,
              textAlign: TextAlign.center,
              style: _body(
                ui,
              ).copyWith(fontSize: ui.fontXs, fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }
}
