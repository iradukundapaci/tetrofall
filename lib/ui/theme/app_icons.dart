abstract final class AppIcons {
  static const _base = 'assets/images/icons';

  // Gameplay & navigation
  static const pause = '$_base/pause.svg';
  static const home = '$_base/home.svg';
  static const chevronRight = '$_base/chevron_right.svg';
  static const settings = '$_base/settings.svg';
  static const trophy = '$_base/trophy.svg';
  static const star = '$_base/star.svg';

  // Currency
  static const coin = '$_base/coin.svg';
  static const coinDetailed = '$_base/coin_detailed.svg';
  static const coinSimple = '$_base/coin_simple.svg';
  static const coinStack = '$_base/coin_stack.svg';

  // Boosters
  static const hammer = '$_base/hammer.svg';
  static const bomb = '$_base/bomb.svg';
  static const drill = '$_base/drill.svg';
  static const lightning = '$_base/lightning.svg';

  // Rewards & progress
  static const treasureChest = '$_base/treasure_chest.svg';
  static const gift = '$_base/gift.svg';
  static const giftSimple = '$_base/gift_simple.svg';
  static const medal = '$_base/medal.svg';
  static const medalOutline = '$_base/medal_outline.svg';
  static const checkCircle = '$_base/check_circle.svg';
  static const checkCircleLight = '$_base/check_circle_light.svg';
  static const lock = '$_base/lock.svg';
  static const video = '$_base/video.svg';

  // Settings
  static const music = '$_base/music.svg';
  static const sound = '$_base/sound.svg';
  static const soundLow = '$_base/sound_low.svg';
  static const soundOff = '$_base/sound_off.svg';
  static const vibrate = '$_base/vibrate.svg';
  static const message = '$_base/message.svg';
  static const bell = '$_base/bell.svg';
  static const restore = '$_base/restore.svg';
  static const shield = '$_base/shield.svg';
  static const document = '$_base/document.svg';
  static const palette = '$_base/palette.svg';
  static const shop = '$_base/shop.svg';

  /// Every icon, for the debug contact sheet.
  static const all = <String, String>{
    'bell': bell,
    'bomb': bomb,
    'check_circle': checkCircle,
    'check_circle_light': checkCircleLight,
    'chevron_right': chevronRight,
    'coin': coin,
    'coin_detailed': coinDetailed,
    'coin_simple': coinSimple,
    'coin_stack': coinStack,
    'document': document,
    'drill': drill,
    'gift': gift,
    'gift_simple': giftSimple,
    'hammer': hammer,
    'home': home,
    'lightning': lightning,
    'lock': lock,
    'medal': medal,
    'medal_outline': medalOutline,
    'message': message,
    'music': music,
    'palette': palette,
    'pause': pause,
    'restore': restore,
    'settings': settings,
    'shield': shield,
    'shop': shop,
    'sound': sound,
    'sound_low': soundLow,
    'sound_off': soundOff,
    'star': star,
    'treasure_chest': treasureChest,
    'trophy': trophy,
    'vibrate': vibrate,
    'video': video,
  };

  /// Render these without a colorFilter — they are deliberately multicolor.
  static const multicolor = <String>{medal, coinDetailed, coinStack};
}
