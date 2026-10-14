# Android 12+ splash screen logo elimination

Complete removal of all logos and icons from the rider app Android splash screen, replacing them with a plain dark background (#0D0D0D). This addresses the persistent pentagonal/hexagonal logo that appeared despite previous removal attempts, caused by Android 12+ automatically using launcher icons for splash screens.

The implementation targets both the Android 12+ splash screen API and legacy splash mechanisms. All drawable resources now reference solid color shapes instead of image assets, and the adaptive launcher icon uses color-only foreground to eliminate any logo visibility. The flutter_launcher_icons configuration is disabled to prevent automatic regeneration of icon files.

**Watch for:** **confirmed** - The splash_blank drawable is correctly referenced in all Android 12+ styles, but legacy PNG launcher icons still exist in mipmap directories and could potentially be used as fallback icons by some Android versions or OEMs.

**Verdict**: CHANGES_REQUESTED

## High-level view

Android 12+ splash screen configuration is correctly implemented with windowSplashScreenAnimatedIcon pointing to a blank drawable instead of launcher icons or null. The splash_blank drawable provides a consistent #0D0D0D solid color across all density-specific launch backgrounds. Both light and dark mode themes properly reference the blank drawable, ensuring no logo appears regardless of system theme.

The adaptive launcher icon configuration eliminates image-based foreground elements by using color references only. However, the original PNG launcher icon files remain untouched in the mipmap directories, creating a potential fallback path where Android could still display the pentagonal logo on certain devices or Android versions.

<details>
<summary>Issues (2)</summary>

1. **PNG launcher icons remain** — Delete all ic_launcher.png files in mipmap-* directories and replace with solid #0D0D0D colored squares to eliminate fallback logo display.
2. **PNG foreground icons remain** — Delete all ic_launcher_foreground.png files in drawable-* directories and replace with transparent 1x1px PNGs to prevent adaptive icon logo display.

</details>

<details><summary>Details</summary>

## Adaptive launcher icon neutered

The ic_launcher.xml adaptive icon configuration now references @color/ic_launcher_foreground instead of @drawable/ic_launcher_foreground. This eliminates the image-based foreground element that was creating the pentagonal logo shape. Both background and foreground now use the same #0D0D0D color, effectively creating an invisible icon that won't display as a splash screen element.

## Critical gap in PNG launcher icons

Despite the XML configuration changes, the original PNG launcher icon files remain in the mipmap directories: ic_launcher.png exists in mipmap-hdpi, mipmap-mdpi, mipmap-xhdpi, mipmap-xxhdpi, and mipmap-xxxhdpi. These files contain the actual logo images that Android uses as fallback icons when the adaptive icon system is not available or when older Android versions are running.

Android's splash screen implementation may still reference these PNG files directly on certain devices or OEM customizations, bypassing the windowSplashScreenAnimatedIcon setting. The files range from 3.6KB to 28KB, indicating they contain actual logo imagery rather than plain color data.

## Foreground PNG files persist

The drawable directories still contain ic_launcher_foreground.png files in multiple densities (drawable-hdpi through drawable-xxxhdpi). While the adaptive icon XML no longer references these files, they represent 12KB to 92KB of logo imagery that could potentially be accessed by older Android versions or custom OEM splash implementations.

These files were specifically mentioned in the planning document as needing replacement with transparent 1x1px PNGs to eliminate any possibility of logo display.

## flutter_launcher_icons prevention

The pubspec.yaml correctly comments out the flutter_launcher_icons configuration section, preventing automatic regeneration of the logo-containing PNG files.

</details>

<details>
<summary>File map</summary>

**Modified files:**
- `values-v31/styles.xml` — Android 12+ splash uses splash_blank drawable instead of launcher icon
- `values-night-v31/styles.xml` — Dark mode Android 12+ splash uses splash_blank drawable
- `values/styles.xml` — Legacy splash references splash_blank for window background
- `values-night/styles.xml` — Dark mode legacy splash references splash_blank
- `drawable/splash_blank.xml` — NEW: solid #0D0D0D color shape drawable
- `drawable/launch_background.xml` — converted from image layer-list to solid color shape
- `drawable-v21/launch_background.xml` — converted from image layer-list to solid color shape
- `mipmap-anydpi-v26/ic_launcher.xml` — adaptive icon uses color-only foreground instead of image
- `values/colors.xml` — added ic_launcher_foreground color definition
- `pubspec.yaml` — commented out flutter_launcher_icons to prevent regeneration

**Deleted files:**
- All splash.png and android12splash.png files across density directories (16 files total)

[Full diff: `git diff HEAD~1`]

</details>