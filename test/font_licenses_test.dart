import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:tetrofall/main.dart';

/// The OFL requires the licence text to ship with the fonts and be surfaced to
/// the user. Nothing in the running app reads these until someone opens
/// Settings → Open source licences, so a broken asset path would go unnoticed
/// until it was a licence breach in a shipped build rather than a bug.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ofl = {
    'Nunito': 'assets/fonts/Nunito/OFL.txt',
    'Baloo 2': 'assets/fonts/Baloo_2/OFL.txt',
  };

  group('OFL licence assets', () {
    for (final entry in ofl.entries) {
      test('${entry.key} ships its licence text', () async {
        // Fails if the path is dropped from pubspec.yaml's `assets:` list —
        // the `fonts:` section bundles only the .ttf files.
        final text = await rootBundle.loadString(entry.value);
        expect(
          text,
          contains('SIL OPEN FONT LICENSE'),
          reason: '${entry.value} is bundled but is not the OFL text',
        );
        expect(text, contains('Copyright'));
      });
    }
  });

  test('registerFontLicenses surfaces both families on the licence page', () async {
    registerFontLicenses();

    final packages = <String>{};
    await for (final entry in LicenseRegistry.licenses) {
      packages.addAll(entry.packages);
    }

    // Flutter's own licences come through the same registry, so this asserts
    // ours were *added*, not that they are all there is.
    expect(packages, containsAll(ofl.keys));
  });
}
