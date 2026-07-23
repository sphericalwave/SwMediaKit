# SwMediaKit

Shared image and video display components for training apps: skill posters
(bundled or user-photographed), thumbnail flipbooks, and instructional-video
playback. Cross-platform (iOS/macOS) with no host-app persistence opinion.

## Requirements

- iOS 17+ / macOS 14+
- Swift 5.9+

## Installation

```swift
.package(url: "https://github.com/sphericalwave/SwMediaKit.git", branch: "main")
```

## Overview

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
