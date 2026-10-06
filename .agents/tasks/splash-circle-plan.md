# Implementation Plan: Fix Flutter Native Splash Screen Logo Circle

## Root Cause Analysis

The issue is that the `flutter_native_splash` configuration in `pubspec.yaml` references `"assets/images/logo_circle.png"` which **does not exist**. The flutter_native_splash package has likely fallen back to using the regular `logo.png` or a default placeholder, causing distortion when it tries to fit a non-circular logo into circular space.

Key findings from exploration:
1. **Missing asset**: `mobile/customer/assets/images/logo_circle.png` does not exist
2. **Original logo**: `mobile/customer/assets/images/logo.png` exists and shows a delivery person with food on a circular white background with black border
3. **Flutter version**: 3.44.8 (stable)
4. **Native splash version**: ^2.3.10 
5. **Android 12+ behavior**: flutter_native_splash uses adaptive icon safe zone (66% of image) which requires proper padding
6. **Current config**: Both base and android_12 sections reference the missing logo_circle.png

The pentagon/distorted shape is likely caused by:
- Missing logo_circle.png causing fallback behavior
- On Android 12+, if any image is used, the adaptive icon masking clips it incorrectly
- The original logo.png has a circular border that may not align with OS masking

## Implementation Plan

- [ ] 1. Create the missing logo_circle.png asset using Dart image processing.
      Generate a perfect circular version of the logo with proper padding for Android 12+ adaptive icon safe zone.
      Files: mobile/customer/assets/images/logo_circle.png (new), mobile/customer/scripts/generate_logo_circle.dart (new)
      Verify: Check that logo_circle.png is created and is 1024x1024 with the logo centered in a 66% safe zone

- [ ] 2. Clean existing flutter_native_splash generated files and regenerate splash resources.
      Remove any cached or incorrectly generated splash files, then run flutter_native_splash generator.
      Files: mobile/customer/android/app/src/main/res/drawable*/*, mobile/customer/android/app/src/main/res/values*/styles.xml
      Verify: `flutter pub run flutter_native_splash:create` completes without errors

- [ ] 3. Test splash screen generation and verify circular logo appears correctly.
      Build the app and check generated Android drawables contain proper circular logo.
      Files: N/A (verification step)
      Verify: Inspect generated splash files in android/app/src/main/res/ and confirm logo appears circular, then test on device/emulator

- [ ] 4. Add fallback verification script for future logo updates.
      Create a script that validates logo_circle.png exists and has correct dimensions before splash generation.
      Files: mobile/customer/scripts/validate_assets.dart (new)
      Verify: `dart run scripts/validate_assets.dart` passes validation checks

## Technical Implementation Details

### Logo Circle Generation (Step 1)
The script will:
- Load the existing logo.png (372KB, shows delivery person on white circle with black border)
- Create a 1024x1024 canvas with transparent background
- Center the logo within a 66% safe zone (677x677 pixels) to avoid Android 12+ adaptive icon clipping
- Apply a circular clip mask to ensure perfect circular shape
- Save as logo_circle.png in assets/images/

### Splash Regeneration (Step 2)
Commands to run:
```bash
cd mobile/customer
flutter clean
flutter pub get
flutter pub run flutter_native_splash:create
```

This will generate proper Android drawables in:
- `android/app/src/main/res/drawable/launch_background.xml`
- `android/app/src/main/res/drawable-*/splash.png` (various densities)
- `android/app/src/main/res/values*/styles.xml` updates

### Verification (Step 3)
Check generated files contain:
- Proper splash.png files in all drawable-* directories
- launch_background.xml references splash image correctly
- Styles.xml LaunchTheme uses updated launch_background
- On Android 12+ (API 31+), check adaptive icon safe zone compliance

### Device Testing
Final verification requires:
1. Uninstall existing app completely (to clear Android cache)
2. Build fresh APK: `flutter build apk --debug`
3. Install on device/emulator
4. Check native splash (before Flutter loads) shows perfect circle
5. Confirm no pentagon/octagon/distortion artifacts

The solution addresses the specific Android 12+ adaptive icon behavior where images are masked to circles/squircles, requiring proper padding to avoid clipping into polygonal shapes.