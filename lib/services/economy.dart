import 'clear_skies_service.dart';
import 'daily_service.dart';
import 'mystery_chest.dart';
import 'storage_service.dart';
import 'wallet_service.dart';

/// Everything the Coin economy is made of, built once in `main()` and passed
/// down as one value — the app uses constructor injection rather than a DI
/// framework, and four separate parameters on every screen would be noise.
class Economy {
  factory Economy(StorageService storage) {
    final wallet = WalletService(storage);
    final chest = MysteryChest(storage, wallet);
    return Economy._(
      wallet: wallet,
      clearSkies: ClearSkiesService(storage),
      chest: chest,
      daily: DailyService(storage, wallet, chest),
    );
  }

  Economy._({
    required this.wallet,
    required this.clearSkies,
    required this.chest,
    required this.daily,
  });

  final WalletService wallet;
  final ClearSkiesService clearSkies;
  final MysteryChest chest;
  final DailyService daily;
}
