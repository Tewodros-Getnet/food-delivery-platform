# Implementation Plan: Restaurant and Rider App Icon and Splash Screen Fixes

## Investigation Summary

The customer app has been successfully configured and serves as the reference implementation. Investigation reveals:

**Current Status:**
- ✅ All three apps (customer, restaurant, rider) have `logo_circle.png` generated at `assets/images/logo_circle.png`
- ✅ All three apps have correct `pubspec.yaml` configurations for `flutter_native_splash` and `flutter_launcher_icons`
- ✅ Restaurant and rider apps have correct `launch_background.xml` (solid color references, not bitmaps)
- ✅ Restaurant and rider apps have correct `colors.xml` with `splash_background: #0D0D0D`
- ✅ Restaurant and rider apps have no unwanted `background.png` files
- ❌ Restaurant and rider apps are missing the `image: ^4.10.1` dev dependency needed for the logo generation script
- ❌ Restaurant and rider apps are missing generated splash screen assets (`splash.png`, `android12splash.png`)
- ❌ Customer app still has `background.png` files and bitmap references in `launch_background.xml` (needs fixing)

**Key Findings:**
- The `mobile/customer/tool/make_circle_logo.dart` script already processes all three apps correctly
- Restaurant and rider apps have proper configuration but missing generated assets
- Customer app configuration is inconsistent (has bitmap references instead of solid color)

## Implementation Steps

### 1. Add Missing Dependencies
Add the `image` dependency to restaurant and rider apps' `pubspec.yaml` dev_dependencies section.
Files: 
- `mobile/restaurant/pubspec.yaml`
- `mobile/rider/pubspec.yaml`

Verify: Check that `image: ^4.10.1` appears in dev_dependencies sections

### 2. Install Dependencies
Run `flutter pub get` in restaurant and rider app directories to install the new dependency.
Files: N/A (command execution)
Verify: `flutter pub get` completes successfully for both apps

### 3. Generate Missing Splash Screen Assets
Run `dart run flutter_native_splash:create` in restaurant and rider app directories to generate splash screen assets.
Files: 
- Restaurant app: `mobile/restaurant/android/app/src/main/res/drawable-*/splash.png` and `android12splash.png`
- Rider app: `mobile/rider/android/app/src/main/res/drawable-*/splash.png` and `android12splash.png`

Verify: Splash asset files are created in all drawable density directories

### 4. Regenerate App Icons
Run `dart run flutter_launcher_icons:main` in restaurant and rider app directories to ensure app icons are properly generated.
Files: 
- Restaurant app: `mobile/restaurant/android/app/src/main/res/drawable-*/ic_launcher_foreground.png`
- Rider app: `mobile/rider/android/app/src/main/res/drawable-*/ic_launcher_foreground.png`

Verify: Icon assets are updated with correct timestamps

### 5. Fix Customer App Launch Background (Consistency Fix)
Update customer app's `launch_background.xml` files to use solid color reference instead of bitmap reference.
Files:
- `mobile/customer/android/app/src/main/res/drawable/launch_background.xml`
- `mobile/customer/android/app/src/main/res/drawable-v21/launch_background.xml`

Replace bitmap references with:
```xml
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item>
        <color android:color="@color/splash_background"/>
    </item>
</layer-list>
```

Verify: Files contain solid color references, not bitmap references

### 6. Remove Unwanted Background Files (Customer App Cleanup)
Delete the `background.png` files from customer app drawable directories.
Files:
- `mobile/customer/android/app/src/main/res/drawable/background.png`
- `mobile/customer/android/app/src/main/res/drawable-v21/background.png`

Verify: Files no longer exist

### 7. Test Build Process
Run a build test for each app to ensure all changes work correctly.
Files: N/A (command execution)
Verify: `flutter build apk --debug` completes successfully for all three apps

## Expected Outcome

After implementation:
- All three apps will have consistent, circular logo splash screens with proper dark background
- All three apps will have properly generated adaptive icons with dark background
- No unwanted bitmap references or background.png files will remain
- The build process will complete successfully for all apps
- The splash screen pentagon/offset issue will be resolved with perfect circular logos