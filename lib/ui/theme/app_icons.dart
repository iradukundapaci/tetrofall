abstract final class AppIcons {
  static const _base = 'assets/images/icons';

  static const pause = '$_base/pause.svg';
  static const home = '$_base/home.svg';
  static const chevronRight = '$_base/chevron_right.svg';
  static const settings = '$_base/settings.svg';
  static const trophy = '$_base/trophy.svg';
  static const star = '$_base/star.svg';

  static const medal = '$_base/medal.svg';
  static const medalOutline = '$_base/medal_outline.svg';
  static const checkCircle = '$_base/check_circle.svg';
  static const checkCircleLight = '$_base/check_circle_light.svg';
  static const lock = '$_base/lock.svg';

  static const music = '$_base/music.svg';
  static const sound = '$_base/sound.svg';
  static const soundLow = '$_base/sound_low.svg';
  static const soundOff = '$_base/sound_off.svg';
  static const vibrate = '$_base/vibrate.svg';
  static const message = '$_base/message.svg';
  static const bell = '$_base/bell.svg';
  static const shield = '$_base/shield.svg';
  static const document = '$_base/document.svg';
  static const palette = '$_base/palette.svg';

  // Boosters. Lucide (ISC), one glyph each, stroked in `currentColor` so a
  // single file takes the ready, muted, greyed and armed tints — see
  // `boosters.md` §9.6 for the map and `tools/ICONS.md` for the licence.
  static const hammer = '$_base/hammer.svg';
  static const bomb = '$_base/bomb.svg';
  static const patch = '$_base/patch.svg';
  static const drill = '$_base/drill.svg';
  static const slide = '$_base/slide.svg';
  static const pillar = '$_base/pillar.svg';
  static const sweep = '$_base/sweep.svg';
  static const lightning = '$_base/lightning.svg';
  static const mortar = '$_base/mortar.svg';
  static const earthquake = '$_base/earthquake.svg';
  static const tilt = '$_base/tilt.svg';
  static const wildfire = '$_base/wildfire.svg';

  /// The rewarded-ad badge on a spent slot (§9.3), and the empty-wallet state
  /// of the booster purchase sheet.
  static const circlePlay = '$_base/circle_play.svg';

  /// Coins — the only currency. Geometry taken from `.icon-coin` in
  /// `screens/shop.html`, redrawn as an all-stroke `currentColor` glyph so it
  /// tints at the call site like the booster icons rather than baking in gold.
  static const coin = '$_base/coin.svg';

  static const all = <String, String>{
    'bell': bell,
    'bomb': bomb,
    'circle_play': circlePlay,
    'coin': coin,
    'drill': drill,
    'earthquake': earthquake,
    'hammer': hammer,
    'lightning': lightning,
    'mortar': mortar,
    'patch': patch,
    'pillar': pillar,
    'slide': slide,
    'sweep': sweep,
    'tilt': tilt,
    'wildfire': wildfire,
    'check_circle': checkCircle,
    'check_circle_light': checkCircleLight,
    'chevron_right': chevronRight,
    'document': document,
    'home': home,
    'lock': lock,
    'medal': medal,
    'medal_outline': medalOutline,
    'message': message,
    'music': music,
    'palette': palette,
    'pause': pause,
    'settings': settings,
    'shield': shield,
    'sound': sound,
    'sound_low': soundLow,
    'sound_off': soundOff,
    'star': star,
    'trophy': trophy,
    'vibrate': vibrate,
  };

  static const multicolor = <String>{medal};
}
