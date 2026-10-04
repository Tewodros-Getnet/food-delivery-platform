# Splash Screen Unification Implementation Review

Unified splash screen implementation across customer, restaurant, and rider Flutter apps to eliminate visual transitions between native Android splash and Flutter splash screens.

The implementation successfully addresses the original problem where users saw two different splash screens during app launch - a white native splash with logo followed by a dark Flutter splash with only a spinner. All three apps now display consistent white backgrounds with circular logos throughout the entire startup sequence. The approach maintains existing router logic while ensuring seamless visual continuity.

**Watch for:** All implementation requirements have been met correctly. No blocking concerns remain.

**Verdict**: APPROVED

## High-level view

The native splash configuration has been properly updated to use white backgrounds (`#FFFFFF`) in all three pubspec.yaml files, replacing the previous dark `#0D0D0D` color. Android styles use a referenced color resource (`@color/splash_background`) that resolves to white in both regular and night mode, ensuring consistency across device theme settings. The Flutter _SplashScreen widgets correctly implement white backgrounds with 180x180 circular logo images using ClipOval for proper circular clipping. All router redirect logic and authentication flows remain unchanged, preserving existing functionality while solving the visual transition issue.

<details>
<summary>Issues (0)</summary>

No issues found.

</details>

<details>
<summary>Details</summary>

## Native splash configuration consistency

All three apps (customer, restaurant, rider) have correctly configured flutter_native_splash in their pubspec.yaml files. The color property uses `"#FFFFFF"` (white) instead of the problematic `"#0D0D0D"` (dark), and the android_12 section properly specifies both `color` and `icon_background_color` as `"#FFFFFF"`. The logo image asset reference (`"assets/images/logo.png"`) is consistent across all apps.

## Android theme uniformity

The LaunchTheme configuration uses `@color/splash_background` rather than hardcoded colors, which correctly resolves to white (`#FFFFFF`) in the colors.xml resource files. Crucially, both values/styles.xml and values-night/styles.xml use the same white background reference, preventing dark mode devices from showing an inconsistent black splash screen. The `android:forceDarkAllowed` is set to false, ensuring the splash remains white regardless of system theme.

## Flutter splash screen implementation

The _SplashScreen widgets across all three apps follow identical patterns: white Scaffold background (`Colors.white`), centered 180x180 SizedBox containing a ClipOval with the logo image using `BoxFit.cover`. The circular clipping ensures the logo appears as a perfect circle as requested. The logo size (180px) provides good visibility without being overwhelming.

## Router logic preservation

The authentication flows, redirect logic, and route definitions remain completely unchanged from the original implementation. The splash screen serves its intended purpose as a loading state during authentication resolution, with proper redirects to appropriate destinations (login, home, setup screens) based on auth status. Navigation patterns for guests, authenticated users, and pending verification states are preserved.

</details>

## File map

<details>
<summary>Files changed</summary>

- **mobile/customer/pubspec.yaml** — Updated flutter_native_splash color to white
- **mobile/restaurant/pubspec.yaml** — Updated flutter_native_splash color to white  
- **mobile/rider/pubspec.yaml** — Updated flutter_native_splash color to white
- **mobile/customer/android/app/src/main/res/values/colors.xml** — Splash background color set to white
- **mobile/restaurant/android/app/src/main/res/values/colors.xml** — Splash background color set to white
- **mobile/rider/android/app/src/main/res/values/colors.xml** — Splash background color set to white
- **mobile/customer/android/app/src/main/res/values-night/styles.xml** — LaunchTheme uses white background
- **mobile/restaurant/android/app/src/main/res/values-night/styles.xml** — LaunchTheme uses white background
- **mobile/rider/android/app/src/main/res/values-night/styles.xml** — LaunchTheme uses white background
- **mobile/customer/lib/core/router/app_router.dart** — _SplashScreen widget with white background and circular logo
- **mobile/restaurant/lib/core/router/app_router.dart** — _SplashScreen widget with white background and circular logo  
- **mobile/rider/lib/core/router/app_router.dart** — _SplashScreen widget with white background and circular logo

</details>