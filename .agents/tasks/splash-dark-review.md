# Splash Screen Dark Theme Unification

Unified splash screen implementation across customer, restaurant, and rider Flutter apps to ensure seamless visual transitions between native Android splash and Flutter splash screens using consistent dark backgrounds.

The implementation successfully addresses the original user concern where different splash screens were showing "different logos" and users could "see or notice the transition of the 2 splashes." All three apps now maintain visual continuity with identical dark #0D0D0D backgrounds throughout the entire startup sequence. Both the native splash (shown before Flutter loads) and Flutter splash (shown during app initialization) now use the same dark theme with circular logo presentation.

**Watch for:** All configuration requirements have been met correctly. No blocking concerns remain.

**Verdict**: APPROVED

## High-level view

Flutter native splash configuration has been properly updated to use dark backgrounds (`#0D0D0D`) across all three pubspec.yaml files, replacing any previous light themes. Android resource files consistently reference the dark splash_background color in values/colors.xml, ensuring uniform appearance regardless of device theme settings. The Android 12+ specific styles properly configure windowSplashScreenBackground and iconBackgroundColor with the dark theme. Flutter _SplashScreen widgets correctly implement the dark background with circular logo presentation using ClipOval for perfect circular clipping as requested. All router logic and authentication flows remain unchanged, preserving existing functionality while solving the visual transition issue.

<details>
<summary>Issues (0)</summary>

No issues found.

</details>

<details>
<summary>Details</summary>

## Flutter native splash configuration alignment

All three apps (customer, restaurant, rider) have correctly configured flutter_native_splash in their pubspec.yaml files. The `color` property uses `"#0D0D0D"` (dark) consistently, and the `android_12` section properly specifies both `color` and `icon_background_color` as `"#0D0D0D"`. The logo image asset reference (`"assets/images/logo.png"`) is consistent across all apps, ensuring the same circular logo appears in both splash screens.

## Android resource consistency

The colors.xml files in values/ directories for all three apps correctly define `splash_background` as `#0D0D0D`. The regular styles.xml files use `@color/splash_background` references for the LaunchTheme windowBackground, ensuring consistent dark appearance. Both values/ and values-night/ styles.xml files reference the same dark color resource, preventing any inconsistency between light and dark device themes.

## Android 12+ splash screen compliance

The values-v31/ and values-night-v31/ styles.xml files across all three apps properly configure the newer Android 12+ splash screen API. The `windowSplashScreenBackground` and `windowSplashScreenIconBackgroundColor` both use the correct `#0D0D0D` color value. This ensures that on Android 12+ devices, the native splash screen maintains the same dark theme as the legacy implementation.

## Flutter splash screen implementation

The _SplashScreen widgets in all three app routers follow the required pattern: dark Scaffold background using `const Color(0xFF0D0D0D)`, centered 180x180 SizedBox containing ClipOval with the logo image using `BoxFit.cover`. The circular clipping ensures the logo appears as a perfect circle as specifically requested. No CircularProgressIndicator or spinner is present, maintaining visual simplicity during the transition.

## Seamless transition achievement

The implementation eliminates the visual jarring between native and Flutter splash screens. Both screens now show identical dark backgrounds with the same circular logo, making the transition imperceptible to users. The 180px logo size provides optimal visibility while the dark background creates a premium, cohesive brand experience across all three apps.

</details>

## File map

<details>
<summary>Files changed</summary>

- **mobile/customer/pubspec.yaml** — flutter_native_splash color updated to #0D0D0D
- **mobile/restaurant/pubspec.yaml** — flutter_native_splash color updated to #0D0D0D  
- **mobile/rider/pubspec.yaml** — flutter_native_splash color updated to #0D0D0D
- **mobile/customer/android/app/src/main/res/values/colors.xml** — splash_background set to #0D0D0D
- **mobile/restaurant/android/app/src/main/res/values/colors.xml** — splash_background set to #0D0D0D
- **mobile/rider/android/app/src/main/res/values/colors.xml** — splash_background set to #0D0D0D
- **mobile/customer/android/app/src/main/res/values-v31/styles.xml** — windowSplashScreenBackground set to #0D0D0D
- **mobile/restaurant/android/app/src/main/res/values-v31/styles.xml** — windowSplashScreenBackground set to #0D0D0D
- **mobile/rider/android/app/src/main/res/values-v31/styles.xml** — windowSplashScreenBackground set to #0D0D0D
- **mobile/customer/android/app/src/main/res/values-night-v31/styles.xml** — windowSplashScreenBackground set to #0D0D0D
- **mobile/restaurant/android/app/src/main/res/values-night-v31/styles.xml** — windowSplashScreenBackground set to #0D0D0D
- **mobile/rider/android/app/src/main/res/values-night-v31/styles.xml** — windowSplashScreenBackground set to #0D0D0D
- **mobile/customer/lib/core/router/app_router.dart** — _SplashScreen backgroundColor updated to Color(0xFF0D0D0D)
- **mobile/restaurant/lib/core/router/app_router.dart** — _SplashScreen backgroundColor updated to Color(0xFF0D0D0D)
- **mobile/rider/lib/core/router/app_router.dart** — _SplashScreen backgroundColor updated to Color(0xFF0D0D0D)

</details>