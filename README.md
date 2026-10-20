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

- `MediaSourceButton` — the one photo button every app uses. On iOS it opens
  the standard action sheet: *Take Photo* (only where a camera exists),
  *Choose from Library*, *Remove Photo* (destructive, only when `onRemove` is
  passed) and *Cancel*. When neither the camera nor Remove applies
  (simulator, camera-less devices, nothing to remove) it skips the sheet and
  goes straight to the library. On macOS it opens the library picker
  directly, with Remove Photo as a row of its own.

  By default it hands back storage-ready JPEG `Data` — both paths run
  `reencodedForStorage` off the main actor, so a host app can't accidentally
  persist a full-resolution capture.

  ```swift
  MediaSourceButton(onRemove: tool.photo == nil ? nil : { tool.photo = nil }) { data in
      tool.photo = data
  }
  ```

  `selectionLimit` controls how many library photos one trip through the
  picker returns — 1 (the default) dismisses on the first tap, higher keeps
  the picker up until *Add*, 0 means no limit. `onImage` fires once per
  photo, in picker order.

  ```swift
  MediaSourceButton(selectionLimit: 0) { data in tool.photos.append(data) }
  ```

  **Every photo goes through a crop step by default** (`crop: .square`):
  pan and pinch it in the frame, then *Use Photo*; a multi-photo pick steps
  through "Photo 1 of 3" with *Skip*. The crop is cut from the original
  pixels. `crop: .ratio(4, 3)` locks another aspect, `crop: .free` opens on
  the photo's own shape with Original / Square / 4:5 / 4:3 / 16:9 to choose
  from, and `crop: .none` skips the step (scans, OCR).

  ```swift
  MediaSourceButton(crop: .free) { data in note.photo = data }
  ```

  `preferredCamera: .front` opens Take Photo on the front camera (selfies);
  the user can still flip it. Default `.rear`; ignored on macOS.

  Callers with their own crop step, videos or library asset ids take the raw
  picks instead: `onCapture` gets the camera's full-resolution JPEG once the
  camera has dismissed (safe to present a crop sheet from), `onLibrary` gets
  the `PhotosPickerItem`s untouched.

  ```swift
  MediaSourceButton(matching: .any(of: [.images, .videos]), selectionLimit: 0,
                    onCapture: { cropQueue.append($0) },
                    onLibrary: { items in Task { await importItems(items) } }) {
      Label("Add Photo", systemImage: "photo.badge.plus")
  }
  ```

- `PhotoCropScreen` / `.photoCropQueue(_:crop:onCropped:)` — the same crop
  step for raw picks: append photo `Data` to the queue and get each cropped
  full-resolution JPEG back (skipped ones are dropped). iOS full-screen, macOS
  sheet.

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
