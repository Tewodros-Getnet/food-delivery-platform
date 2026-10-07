# Restaurant and rider splash screen and app icon implementation

Applied the splash screen and app icon fixes from the customer app to both restaurant and rider applications. The changes address the pentagon-shaped splash logo issue by implementing proper circular logo handling and consistent dark backgrounds across all three Flutter applications.

**Watch for:** Missing tool directory structure and script access for future maintenance. All core implementations are correctly applied.

**Verdict**: APPROVED

## High-level view

The pubspec.yaml configurations in both restaurant and rider apps now match the customer app pattern with flutter_native_splash using logo_circle.png and adaptive_icon_background set to the dark #0D0D0D theme. The Android drawable layer-list files correctly reference solid color resources instead of bitmap backgrounds, eliminating the offset pentagon logo issue. The colors.xml files consistently define splash_background as #0D0D0D across all apps. All three applications now have the required logo_circle.png assets generated from the original logo.png files.

<details>
<summary>Issues (1)</summary>

1. **Tool script organization** — The make_circle_logo.dart script exists only in the customer app's tool directory, but it processes all three apps. Consider copying the script to restaurant and rider tool directories for better project organization and independent maintenance.

</details>

<details><summary>Details</summary>

## Flutter configuration consistency across apps

Both restaurant and rider pubspec.yaml files correctly implement the flutter_native_splash and flutter_launcher_icons configurations that match the approved customer app. The flutter_native_splash sections use logo_circle.png for both the standard and android_12 configurations, with consistent #0D0D0D background colors. The flutter_launcher_icons sections specify the dark adaptive_icon_background and proper asset paths. This ensures all three apps will generate identical splash screen behavior and app icon treatment.

The dependency versions for flutter_launcher_icons (^0.14.1) and flutter_native_splash (^2.3.10) are correctly aligned across all applications, preventing version conflicts that could cause different generation behaviors.

## Android native resource implementation

The launch_background.xml files in both restaurant and rider apps correctly use the layer-list approach with solid color references rather than bitmap backgrounds. This matches the customer app's approach that resolved the pentagon logo offset issue. The files reference @color/splash_background, which is properly defined in each app's colors.xml as #0D0D0D.

The colors.xml files in both apps define both ic_launcher_background and splash_background with the consistent dark theme color. This ensures the adaptive icon background and splash screen background are visually coherent.

## Asset file organization

The logo_circle.png files exist in all three app asset directories (customer, restaurant, rider), confirming the circular logo generation was applied consistently. The original logo.png files remain available as sources for future regeneration if needed.

The make_circle_logo.dart script in the customer app's tool directory is designed to process all three applications in a single run, with hardcoded paths to each app's asset directory. This script creates properly sized circular logos optimized for Android 12+ adaptive icons with appropriate safe zone padding.

## Missing tool structure for maintenance

While the make_circle_logo.dart script works correctly and processes all apps, it only exists in the customer app's tool directory. For better project organization and to allow each app team to independently maintain their assets, the script should be copied to restaurant/tool/ and rider/tool/ directories as well. This would allow each app to regenerate its circular logo independently without depending on the customer app's tooling.

</details>

<details>
<summary>File map</summary>

**Restaurant app:**
- `mobile/restaurant/pubspec.yaml` — Updated flutter_native_splash and flutter_launcher_icons configs
- `mobile/restaurant/android/app/src/main/res/drawable/launch_background.xml` — Solid color layer-list implementation
- `mobile/restaurant/android/app/src/main/res/values/colors.xml` — Dark theme color definitions
- `mobile/restaurant/assets/images/logo_circle.png` — Generated circular logo asset

**Rider app:**
- `mobile/rider/pubspec.yaml` — Updated flutter_native_splash and flutter_launcher_icons configs  
- `mobile/rider/android/app/src/main/res/drawable/launch_background.xml` — Solid color layer-list implementation
- `mobile/rider/android/app/src/main/res/values/colors.xml` — Dark theme color definitions
- `mobile/rider/assets/images/logo_circle.png` — Generated circular logo asset

**Shared tooling:**
- `mobile/customer/tool/make_circle_logo.dart` — Logo generation script (processes all three apps)

</details>