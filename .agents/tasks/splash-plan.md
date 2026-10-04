# Splash Screen Unification Implementation Plan

## Problem Analysis

Currently users see two distinct splash screens during app launch:
1. **Native Android splash** (before Flutter loads): White background with logo from flutter_native_splash
2. **Flutter splash** (after Flutter loads): Dark `#0D0D0D` background with only a small orange spinner

The visual transition between these two is jarring and inconsistent. Both screens need to be identical.

## Investigation Findings

### Current State per App:
- **All 3 apps (customer, restaurant, rider):**
  - `pubspec.yaml`: `flutter_native_splash` uses `color: "#0D0D0D"` (dark) with `image: "assets/images/logo.png"`
  - `styles.xml`: LaunchTheme uses `@android:color/white` (white background)
  - `values-night/styles.xml`: LaunchTheme uses `@android:color/black` (causes dark splash in dark mode)
  - `_SplashScreen` widget: Dark `Color(0xFF0D0D0D)` background with 24x24 orange spinner, no logo

### Core Issue:
1. `flutter_native_splash` config generates dark background but `styles.xml` overrides to white
2. Flutter `_SplashScreen` shows dark background with no logo
3. Night mode styles cause additional inconsistency

## Implementation Plan

### Phase 1: Update Native Splash Configuration

- [ ] 1. Update flutter_native_splash config in all three pubspec.yaml files
      Change `color: "#0D0D0D"` to `color: "#FFFFFF"` to use white background.
      Keep existing `image: "assets/images/logo.png"` and android_12 config.
      Files: 
      - `mobile/customer/pubspec.yaml`
      - `mobile/restaurant/pubspec.yaml`  
      - `mobile/rider/pubspec.yaml`
      Verify: No immediate verification needed (config change only)

- [ ] 2. Fix night mode styles.xml to use white background consistently
      Change `android:windowBackground` from `@android:color/black` to `@android:color/white` in values-night/styles.xml
      This ensures splash is always white regardless of system dark mode.
      Files:
      - `mobile/customer/android/app/src/main/res/values-night/styles.xml`
      - `mobile/restaurant/android/app/src/main/res/values-night/styles.xml`
      - `mobile/rider/android/app/src/main/res/values-night/styles.xml`
      Verify: No immediate verification needed (XML change only)

### Phase 2: Regenerate Native Splash Assets

- [ ] 3. Regenerate native splash assets for Customer app
      Run `dart run flutter_native_splash:create` to regenerate drawable XML and PNG files with white background
      Files: Regenerates files in `mobile/customer/android/app/src/main/res/drawable*/`
      Verify: Check that `background.png` is now white and `launch_background.xml` references correct files

- [ ] 4. Regenerate native splash assets for Restaurant app
      Run `dart run flutter_native_splash:create` to regenerate drawable XML and PNG files with white background
      Files: Regenerates files in `mobile/restaurant/android/app/src/main/res/drawable*/`
      Verify: Check that `background.png` is now white and `launch_background.xml` references correct files

- [ ] 5. Regenerate native splash assets for Rider app
      Run `dart run flutter_native_splash:create` to regenerate drawable XML and PNG files with white background  
      Files: Regenerates files in `mobile/rider/android/app/src/main/res/drawable*/`
      Verify: Check that `background.png` is now white and `launch_background.xml` references correct files

### Phase 3: Update Flutter Splash Screens

- [ ] 6. Replace _SplashScreen widget in Customer app
      Change background from `Color(0xFF0D0D0D)` to `Colors.white`, add centered logo image at ~120x120 size
      Replace CircularProgressIndicator with Image.asset('assets/images/logo.png') in a Container with circular clip
      Files: `mobile/customer/lib/core/router/app_router.dart`
      Verify: `flutter run --debug` customer app and observe splash screen matches native splash

- [ ] 7. Replace _SplashScreen widget in Restaurant app  
      Apply same changes as Customer: white background, centered logo image instead of spinner
      Files: `mobile/restaurant/lib/core/router/app_router.dart` 
      Verify: `flutter run --debug` restaurant app and observe splash screen matches native splash

- [ ] 8. Replace _SplashScreen widget in Rider app
      Apply same changes as Customer: white background, centered logo image instead of spinner  
      Files: `mobile/rider/lib/core/router/app_router.dart`
      Verify: `flutter run --debug` rider app and observe splash screen matches native splash

### Phase 4: Final Testing

- [ ] 9. Test complete splash screen flow for all apps
      Build and test each app to ensure seamless transition from native to Flutter splash
      Test both light and dark system modes to ensure consistency
      Files: No code changes, testing only
      Verify: Visual inspection shows no visible transition between native and Flutter splash screens

## Technical Details

### New _SplashScreen Widget Code:
```dart
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Container(
          width: 120,
          height: 120,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
          ),
          clipBehavior: Clip.hardEdge,
          child: Image.asset(
            'assets/images/logo.png',
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
```

### Updated pubspec.yaml flutter_native_splash:
```yaml
flutter_native_splash:
  color: "#FFFFFF"  # Changed from "#0D0D0D"
  image: "assets/images/logo.png"
  android_12:
    image: "assets/images/logo.png" 
    color: "#FFFFFF"  # Changed from "#0D0D0D"
```

### Updated values-night/styles.xml:
```xml
<style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">
    <item name="android:windowBackground">@android:color/white</item>  <!-- Changed from black -->
    <!-- ... other items unchanged ... -->
</style>
```

## Success Criteria

1. Native Android splash shows white background with centered circular logo
2. Flutter _SplashScreen shows identical white background with same circular logo
3. No visible transition or flicker between the two splash screens
4. Consistency maintained in both light and dark system modes
5. All three apps (customer, restaurant, rider) have identical splash behavior

## Dependencies

Each step builds on the previous:
- Steps 1-2 prepare configuration  
- Steps 3-5 must run after steps 1-2 to regenerate with correct config
- Steps 6-8 implement Flutter UI to match the regenerated native splash
- Step 9 validates the complete integration