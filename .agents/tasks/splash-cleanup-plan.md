# Splash Screen Complete Cleanup Plan

This plan removes ALL splash screen assets and implementations from the 3 Flutter apps (customer, restaurant, rider) to eliminate the visible transition between native Android splash and Flutter splash screens.

## Customer App (mobile/customer/)

### pubspec.yaml Changes
- **File:** `mobile/customer/pubspec.yaml`
- **Action:** Remove `flutter_native_splash: ^2.3.10` from dev_dependencies
- **Action:** Remove entire `flutter_native_splash:` configuration block (lines with color, android_12 settings)

### Android Native Splash Assets - DELETE FILES
- **File:** `mobile/customer/android/app/src/main/res/drawable/background.png` - DELETE
- **File:** `mobile/customer/android/app/src/main/res/drawable-v21/background.png` - DELETE
- **File:** `mobile/customer/android/app/src/main/res/drawable/launch_background.xml` - DELETE
- **File:** `mobile/customer/android/app/src/main/res/drawable-v21/launch_background.xml` - DELETE

### Android Styles - MODIFY FILES
- **File:** `mobile/customer/android/app/src/main/res/values/styles.xml`
  - **Action:** Change LaunchTheme parent from `@android:style/Theme.Black.NoTitleBar` to `@android:style/Theme.Light.NoTitleBar`
  - **Action:** Remove `<item name="android:windowBackground">@color/splash_background</item>` line
  - **Action:** Change NormalTheme parent from `@android:style/Theme.Black.NoTitleBar` to `@android:style/Theme.Light.NoTitleBar`  
  - **Action:** Remove `<item name="android:windowBackground">@color/splash_background</item>` line

- **File:** `mobile/customer/android/app/src/main/res/values-night/styles.xml`
  - **Action:** Change LaunchTheme parent from `@android:style/Theme.Black.NoTitleBar` to `@android:style/Theme.Light.NoTitleBar`
  - **Action:** Remove `<item name="android:windowBackground">@color/splash_background</item>` line
  - **Action:** Change NormalTheme parent from `@android:style/Theme.Black.NoTitleBar` to `@android:style/Theme.Light.NoTitleBar`
  - **Action:** Remove `<item name="android:windowBackground">@color/splash_background</item>` line

- **File:** `mobile/customer/android/app/src/main/res/values-v31/styles.xml`
  - **Action:** Remove `<item name="android:windowSplashScreenBackground">#0D0D0D</item>` line
  - **Action:** Remove `<item name="android:windowSplashScreenIconBackgroundColor">#0D0D0D</item>` line

- **File:** `mobile/customer/android/app/src/main/res/values-night-v31/styles.xml`
  - **Action:** Remove `<item name="android:windowSplashScreenBackground">#0D0D0D</item>` line
  - **Action:** Remove `<item name="android:windowSplashScreenIconBackgroundColor">#0D0D0D</item>` line

### Android Colors - MODIFY FILE
- **File:** `mobile/customer/android/app/src/main/res/values/colors.xml`
  - **Action:** Remove `<color name="splash_background">#0D0D0D</color>` line
  - **Action:** Keep `<color name="ic_launcher_background">#0D0D0D</color>` (used for app icon)

### Flutter Router - MODIFY FILE
- **File:** `mobile/customer/lib/core/router/app_router.dart`
  - **Action:** Change `initialLocation: '/splash'` to `initialLocation: '/home'` or appropriate default
  - **Action:** Remove entire `/splash` GoRoute entry (path: '/splash', builder with _SplashScreen)
  - **Action:** Remove `_SplashScreen` class completely
  - **Action:** Update redirect logic to remove all `/splash` references and conditions
  - **Action:** Remove `if (loc == '/splash')` conditions in all auth status cases

## Restaurant App (mobile/restaurant/)

### pubspec.yaml Changes
- **File:** `mobile/restaurant/pubspec.yaml`
- **Action:** Remove `flutter_native_splash: ^2.3.10` from dev_dependencies
- **Action:** Remove entire `flutter_native_splash:` configuration block

### Android Native Splash Assets - DELETE FILES
- **File:** `mobile/restaurant/android/app/src/main/res/drawable/background.png` - DELETE
- **File:** `mobile/restaurant/android/app/src/main/res/drawable-v21/background.png` - DELETE
- **File:** `mobile/restaurant/android/app/src/main/res/drawable/launch_background.xml` - DELETE
- **File:** `mobile/restaurant/android/app/src/main/res/drawable-v21/launch_background.xml` - DELETE

### Android Styles - MODIFY FILES
- **File:** `mobile/restaurant/android/app/src/main/res/values/styles.xml`
  - **Action:** Remove splash-related styling, change to standard Android theme
  - **Action:** Remove any `android:windowBackground` references to splash colors

- **File:** `mobile/restaurant/android/app/src/main/res/values-night/styles.xml`
  - **Action:** Remove splash-related styling, change to standard Android theme

- **File:** `mobile/restaurant/android/app/src/main/res/values-v31/styles.xml`
  - **Action:** Remove Android 12+ splash screen configurations

- **File:** `mobile/restaurant/android/app/src/main/res/values-night-v31/styles.xml`
  - **Action:** Remove Android 12+ splash screen configurations

### Android Colors - MODIFY FILE
- **File:** `mobile/restaurant/android/app/src/main/res/values/colors.xml`
  - **Action:** Remove `<color name="splash_background">#0D0D0D</color>` line
  - **Action:** Keep `<color name="ic_launcher_background">#0D0D0D</color>` (used for app icon)

### Flutter Router - MODIFY FILE
- **File:** `mobile/restaurant/lib/core/router/app_router.dart`
  - **Action:** Change `initialLocation: '/splash'` to appropriate default route
  - **Action:** Remove `/splash` GoRoute entry 
  - **Action:** Remove `_SplashScreen` class completely
  - **Action:** Update redirect logic to remove all `/splash` references

## Rider App (mobile/rider/)

### pubspec.yaml Changes
- **File:** `mobile/rider/pubspec.yaml`
- **Action:** Remove `flutter_native_splash: ^2.3.10` from dev_dependencies
- **Action:** Remove entire `flutter_native_splash:` configuration block

### Android Native Splash Assets - DELETE FILES
- **File:** `mobile/rider/android/app/src/main/res/drawable/background.png` - DELETE
- **File:** `mobile/rider/android/app/src/main/res/drawable-v21/background.png` - DELETE
- **File:** `mobile/rider/android/app/src/main/res/drawable/launch_background.xml` - DELETE
- **File:** `mobile/rider/android/app/src/main/res/drawable-v21/launch_background.xml` - DELETE

### Android Styles - MODIFY FILES
- **File:** `mobile/rider/android/app/src/main/res/values/styles.xml`
  - **Action:** Remove splash-related styling, change to standard Android theme

- **File:** `mobile/rider/android/app/src/main/res/values-night/styles.xml`
  - **Action:** Remove splash-related styling, change to standard Android theme

- **File:** `mobile/rider/android/app/src/main/res/values-v31/styles.xml`
  - **Action:** Remove Android 12+ splash screen configurations

- **File:** `mobile/rider/android/app/src/main/res/values-night-v31/styles.xml`
  - **Action:** Remove Android 12+ splash screen configurations

### Android Colors - MODIFY FILE
- **File:** `mobile/rider/android/app/src/main/res/values/colors.xml`
  - **Action:** Remove `<color name="splash_background">#0D0D0D</color>` line
  - **Action:** Keep `<color name="ic_launcher_background">#0D0D0D</color>` (used for app icon)

### Flutter Router - MODIFY FILE
- **File:** `mobile/rider/lib/core/router/app_router.dart`
  - **Action:** Change `initialLocation: '/splash'` to appropriate default route
  - **Action:** Remove `/splash` GoRoute entry
  - **Action:** Remove `_SplashScreen` class completely  
  - **Action:** Update redirect logic to remove all `/splash` references

## Files to Clean (Generated Assets)
Check for and remove any automatically generated splash screen files in all 3 apps:
- Any `flutter_native_splash_*.png` files in drawable directories
- Any `styles_*.xml` backup files created by flutter_native_splash

## Verification Steps
After cleanup:
1. Run `flutter clean` in each app directory
2. Run `flutter pub get` in each app directory  
3. Build and test each app to ensure no splash transition is visible
4. Verify app icons still display correctly
5. Check that apps launch directly to their main screens without intermediate splash screens

## Important Notes
- This cleanup completely removes the native Android splash screen implementation
- Apps will launch directly to their Flutter UI without any intermediate splash
- App launcher icons are preserved (ic_launcher_* files are kept)
- The visible transition between native and Flutter splash screens will be eliminated
- All 3 apps (customer, restaurant, rider) follow the same cleanup pattern

## Total Files Affected
- **DELETE:** 12 files (4 per app: 2 background.png, 2 launch_background.xml)
- **MODIFY:** 21 files (7 per app: pubspec.yaml, 4 styles.xml variants, 1 colors.xml, 1 app_router.dart)