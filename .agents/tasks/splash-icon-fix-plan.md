# Implementation Plan: Fix Splash Screen Transition and App Icons

## Problem Analysis

Based on code investigation, I found the root cause of the visible splash screen transition and distorted app icons:

1. **Splash Screen Mismatch**: All three apps (customer, restaurant, rider) use different logo shapes between native Android splash and Flutter splash:
   - **Native Android splash**: Uses `logo.png` (square/rectangular logo) via adaptive icons
   - **Flutter splash**: Uses `logo_circle.png` (circular logo)
   - **Result**: Users see a jarring transition from square→circle logo shapes

2. **Current Configuration Issues**:
   - `pubspec.yaml` has `flutter_native_splash` with `image: "assets/images/logo_circle.png"` 
   - Multiple generated splash drawable files exist (splash.png, android12splash.png) across all density folders
   - `launch_background.xml` references these generated splash drawables
   - Adaptive icons use `logo.png` while splash uses `logo_circle.png`

3. **App Icon Issues**: Likely caused by incorrect adaptive icon configuration or mismatched logo dimensions

## Solution Approach

**New Strategy**: Eliminate the native Android splash image entirely → solid black splash screen → Flutter splash with circular logo. This removes any visual mismatch.

## Implementation Plan

- [ ] 1. **Remove splash images from Customer app pubspec.yaml**
      Remove the `image:` line from `flutter_native_splash` section in pubspec.yaml, keeping only the black background color.
      Files: `mobile/customer/pubspec.yaml`
      Verify: Check that pubspec.yaml has only `color: "#0D0D0D"` under flutter_native_splash (no image references)

- [ ] 2. **Clean up Customer app adaptive icon configuration**
      Ensure adaptive_icon_foreground uses the correct logo.png and background is solid black.
      Files: `mobile/customer/pubspec.yaml`
      Verify: Confirm adaptive icon settings use consistent logo file and black background

- [ ] 3. **Regenerate Customer app splash screen assets**
      Run `dart run flutter_native_splash:create` to regenerate splash screens without logo images.
      Files: All files under `mobile/customer/android/app/src/main/res/drawable*` (splash-related files will be updated/removed)
      Verify: Check that generated drawable files don't contain splash logo images, only solid color background

- [ ] 4. **Regenerate Customer app launcher icons**
      Run `dart run flutter_launcher_icons:main` to regenerate clean app icons.
      Files: All files under `mobile/customer/android/app/src/main/res/mipmap*`
      Verify: Check that app icon files are properly generated and not distorted

- [ ] 5. **Apply same fixes to Restaurant app**
      Repeat steps 1-4 for the restaurant app with identical configuration changes.
      Files: `mobile/restaurant/pubspec.yaml`, `mobile/restaurant/android/app/src/main/res/drawable*`, `mobile/restaurant/android/app/src/main/res/mipmap*`
      Verify: Run both generator commands and confirm clean generation for restaurant app

- [ ] 6. **Apply same fixes to Rider app**
      Repeat steps 1-4 for the rider app with identical configuration changes.
      Files: `mobile/rider/pubspec.yaml`, `mobile/rider/android/app/src/main/res/drawable*`, `mobile/rider/android/app/src/main/res/mipmap*`
      Verify: Run both generator commands and confirm clean generation for rider app

- [ ] 7. **Clean build and test all apps**
      Clean build directories and build APKs for all three apps to test the splash screen behavior.
      Files: N/A (build process)
      Verify: For each app: 
      - Run `flutter clean` 
      - Run `flutter build apk --debug`
      - Install APK on device and verify: solid black native splash → circular logo Flutter splash (no visible transition)
      - Verify app icons appear properly in launcher without distortion

## Key Configuration Changes

### Before (causing issues):
```yaml
flutter_native_splash:
  color: "#0D0D0D"
  image: "assets/images/logo_circle.png"  # ← This creates the transition problem
  android_12:
    image: "assets/images/logo_circle.png"
```

### After (solution):
```yaml
flutter_native_splash:
  color: "#0D0D0D"
  # No image: line at all - pure solid color splash
  android_12:
    icon_background_color: "#0D0D0D"
    color: "#0D0D0D"
    # No image: line - pure solid color for Android 12+ too
```

## Expected Result

- **Native Android splash**: Solid black screen (#0D0D0D) with NO logo
- **Flutter splash**: Black background with circular logo in center  
- **User experience**: Black → black-with-circular-logo (seamless transition, no shape mismatch)
- **App icons**: Clean, properly-fitted icons in launcher without distortion

## Build Commands

Each app uses Flutter's standard build process:
- Generator commands: `dart run flutter_native_splash:create`, `dart run flutter_launcher_icons:main`
- Build commands: `flutter clean`, `flutter build apk --debug`
- Test: Install generated APK and observe splash screen behavior on real device

## Files Affected Per App

**Customer App:**
- `mobile/customer/pubspec.yaml` (configuration changes)
- `mobile/customer/android/app/src/main/res/drawable*/` (regenerated splash assets)
- `mobile/customer/android/app/src/main/res/mipmap*/` (regenerated icon assets)

**Restaurant App:**
- `mobile/restaurant/pubspec.yaml` (configuration changes)  
- `mobile/restaurant/android/app/src/main/res/drawable*/` (regenerated splash assets)
- `mobile/restaurant/android/app/src/main/res/mipmap*/` (regenerated icon assets)

**Rider App:**
- `mobile/rider/pubspec.yaml` (configuration changes)
- `mobile/rider/android/app/src/main/res/drawable*/` (regenerated splash assets)
- `mobile/rider/android/app/src/main/res/mipmap*/` (regenerated icon assets)