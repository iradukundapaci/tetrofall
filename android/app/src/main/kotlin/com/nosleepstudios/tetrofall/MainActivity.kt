package com.nosleepstudios.tetrofall

import android.os.Bundle
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 15 draws every app edge to edge once it targets SDK 35, and
        // Android 16 removes the opt-out. Opting in explicitly gives Android 9-14
        // the same window as 15+, so there is one layout to reason about; the
        // Dart side already reads the system insets from `viewPadding`
        // (see `_GameplayBody` and `UiScale`).
        //
        // This is `enableEdgeToEdge()` spelled out. That helper is an extension
        // on `ComponentActivity`, which `FlutterActivity` is not, and moving to
        // `FlutterFragmentActivity` to get it would change the host every plugin
        // sees. It also sets bar colours through `Window.setStatusBarColor` /
        // `setNavigationBarColor`, which Android 15 deprecates — unnecessary
        // here, because the launch theme draws no system-bar backgrounds
        // (`windowDrawsSystemBarBackgrounds=false`), so there is nothing to make
        // transparent.
        WindowCompat.setDecorFitsSystemWindows(window, false)

        // Light icons, always. The app is dark-only, and the default follows the
        // *system* theme, which in light mode paints dark status-bar icons over
        // the dark wood background and makes them unreadable.
        WindowInsetsControllerCompat(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
        }

        super.onCreate(savedInstanceState)
    }
}
