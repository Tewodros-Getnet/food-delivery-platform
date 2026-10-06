# Flutter splash screen and app icon fixes

Comprehensive fix for Gradle build failures caused by corrupted bitmap references in splash screen configurations and app icon offset issues. The changes eliminate the "Could not read workspace metadata" errors and resolve the customer app icon positioning problem.

**Watch for:** All critical structural fixes are correctly implemented. The splash screen configurations now use solid color references instead of problematic bitmap references, the customer app icon background is corrected from white to dark, and all unused assets are cleaned up. **Verdict**: APPROVED

## High-level view

The Gradle build failures stemmed from corrupted bitmap references in launch_background.xml files across all three Flutter apps (customer, restaurant, rider). These files previously referenced background.png images that were causing workspace metadata corruption in Gradle's transform cache. The fix standardizes all splash screens to use solid color references with a consistent dark theme (#0D0D0D).

The customer app icon offset was caused by a white adaptive_icon_background (#FFFFFF) creating visual displacement against the app's dark branding. This has been corrected to match the dark theme (#0D0D0D).

Root directory cleanup removes orphaned PNG assets (customer.png, restaurant.png, rider.png) that were duplicating app-specific resources and potentially causing confusion in asset resolution.

<details>
<summary>Issues (0)</summary>

No issues found. All fixes are correctly implemented.

</details>

<details>
<summary>Details</summary>

## Splash screen bitmap elimination

All launch_background.xml files across the customer, restaurant, and rider apps now use the standardized solid color format. Previously, these files contained references to background.png bitmap resources that were corrupting Gradle's workspace metadata cache, leading to the build failures with "Could not read workspace metadata" errors.

The corrected format uses a simple layer-list with a color item referencing `@color/splash_background`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item>
        <color android:color="@color/splash_background"/>
    </item>
</layer-list>
```

This pattern is consistently applied to:
- `mobile/customer/android/app/src/main/res/drawable/launch_background.xml`
- `mobile/restaurant/android/app/src/main/res/drawable/launch_background.xml` 
- `mobile/restaurant/android/app/src/main/res/drawable-v21/launch_background.xml`
- `mobile/rider/android/app/src/main/res/drawable/launch_background.xml`
- `mobile/rider/android/app/src/main/res/drawable-v21/launch_background.xml`

The customer app lacks a drawable-v21 variant, which is normal - not all apps require API level-specific splash configurations.

## Customer app icon offset correction

The customer app's pubspec.yaml flutter_launcher_icons configuration previously used `adaptive_icon_background: "#FFFFFF"`, creating a white background that caused the app icon to appear offset against darker system themes and launcher backgrounds. This has been corrected to `adaptive_icon_background: "#0D0D0D"` to match the app's dark branding consistently.

The launcher icons were successfully regenerated after this change, ensuring the new background color is applied to all generated icon variants.

## Background image cleanup

All background.png files have been removed from drawable directories where they previously existed:
- `mobile/restaurant/android/app/src/main/res/drawable/background.png` (deleted)
- `mobile/restaurant/android/app/src/main/res/drawable-v21/background.png` (deleted)
- `mobile/rider/android/app/src/main/res/drawable/background.png` (deleted)
- `mobile/rider/android/app/src/main/res/drawable-v21/background.png` (deleted)

The customer app did not have these files, indicating it was already configured differently or never had bitmap splash resources.

## Root directory asset cleanup

Three orphaned PNG files in the root assets directory have been removed:
- `c:\food-delivery-platform-main\assets\customer.png`
- `c:\food-delivery-platform-main\assets\restaurant.png`
- `c:\food-delivery-platform-main\assets\rider.png`

These appear to have been leftover from earlier development phases and were not referenced by the current app configurations. Their removal eliminates potential confusion in asset resolution.

## Color resource consistency

The customer app's `colors.xml` now properly defines `splash_background` as "#0D0D0D", matching the color used across all splash configurations. This ensures consistent theming and eliminates any possibility of undefined color references.

</details>

<details>
<summary>File map</summary>

**Configuration files:**
- `mobile/customer/pubspec.yaml` — corrected adaptive_icon_background from white to dark
- `mobile/customer/android/app/src/main/res/values/colors.xml` — added splash_background color definition

**Launch background files (standardized to solid color format):**
- `mobile/customer/android/app/src/main/res/drawable/launch_background.xml`
- `mobile/restaurant/android/app/src/main/res/drawable/launch_background.xml`
- `mobile/restaurant/android/app/src/main/res/drawable-v21/launch_background.xml`
- `mobile/rider/android/app/src/main/res/drawable/launch_background.xml`
- `mobile/rider/android/app/src/main/res/drawable-v21/launch_background.xml`

**Removed files:**
- Various `background.png` files from drawable directories
- Root directory PNG assets: `customer.png`, `restaurant.png`, `rider.png`

</details>