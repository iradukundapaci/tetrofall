abstract final class AppIcons {
  static const _base = 'assets/images/icons';

  static const pause = '$_base/pause.svg';
  static const home = '$_base/home.svg';
  static const chevronRight = '$_base/chevron_right.svg';
  static const settings = '$_base/settings.svg';
  static const trophy = '$_base/trophy.svg';
  static const star = '$_base/star.svg';

  /// The tutorial's pointing hand. Two-tone on purpose — a cream palm with a
  /// dark outline reads against the board's lit wood, where a single-colour
  /// silhouette would not.
  static const handPoint = '$_base/hand_point.svg';

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

  static const all = <String, String>{
    'bell': bell,
    'check_circle': checkCircle,
    'check_circle_light': checkCircleLight,
    'chevron_right': chevronRight,
    'document': document,
    'hand_point': handPoint,
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

  static const multicolor = <String>{medal, handPoint};
}
