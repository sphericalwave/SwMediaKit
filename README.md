# SwMediaKit

Shared image and video components for training apps: photo capture and picking,
skill posters (bundled or user-photographed), thumbnail flipbooks, and
instructional-video playback. Cross-platform (iOS/macOS) with no host-app
persistence opinion.

## Requirements

- iOS 17+ / macOS 14+
- Swift 5.9+

## Installation

```swift
.package(url: "https://github.com/sphericalwave/SwMediaKit.git", branch: "main")
```

## Overview

### Capture

- `MediaSourceButton` — one "Add Photo" button that offers *Take Photo* /
  *Choose from Library*, and hands back storage-ready JPEG `Data`. Where no
  camera exists (simulator, macOS, camera-less devices) it skips the dialog and
  goes straight to the library, so there is never a dead "Take Photo" row.
  Both paths run `reencodedForStorage` off the main actor, so a host app can't
  accidentally persist a full-resolution capture.

  ```swift
  MediaSourceButton { data in tool.photo = data }
  ```

  `selectionLimit` controls how many library photos one trip through the
  picker returns — 1 (the default) dismisses on the first tap, higher keeps
  the picker up until *Add*, 0 means no limit. `onImage` fires once per
  photo, in picker order.

  ```swift
  MediaSourceButton(selectionLimit: 0) { data in tool.photos.append(data) }
  ```

- `CameraPicker` — the system camera (`UIImagePickerController(.camera)`)
  wrapped for SwiftUI, delivering full-resolution JPEG `Data`. iOS only.
  Prefer `MediaSourceButton`; reach for this directly only if you need the
  camera without the source dialog.

**Host-app requirement:** the camera path needs `NSCameraUsageDescription` in
the app's Info.plist — SPM cannot inject it, and the system traps without it.
Library picking needs no permission key (`PhotosPicker` runs out of process).

### Display

- `PosterGallery` — paged gallery of bundle-named images, with page dots when
  there's more than one.
- `PosterThumbnail` — small square thumbnail: a bundle-image flipbook, a
  decoded custom-photo flipbook, or a single image, with an SF Symbol
  fallback.
- `AnimatedPoster` — "flipbook" poster cycling bundle-named images or decoded
  custom photos at ~3fps, with a pause toggle.
- `ImageCompression` — downsampling + storage re-encoding for photo-picker
  images, so a full-resolution photo never gets decoded/stored at native size
  just to display at thumbnail size. Call off the main actor.
- `PlatformImage` — `UIImage`/`NSImage` type alias + `Image(platformImage:)`,
  shared between iOS and macOS targets.
- `BundledVideoPlayer` — lifecycle-correct `AVPlayer` for a bundled video
  resource; shows a "coming soon" placeholder when the resource isn't bundled
  yet.
- `InstructionalVideoSheet` — full-screen chrome around `BundledVideoPlayer`,
  optionally seeked to a chapter timecode.

## Dependencies

None.
