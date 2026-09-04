# SaveDuk ⚡

> **High-Performance, Privacy-First, On-Device Social Media Media Downloader & Ad-Free Music Suite for Android**

SaveDuk is a native Android application built with Flutter that operates **100% locally with zero external proxy servers, zero scraping APIs, and zero user tracking**. 

All URL parsing, stream extraction, media downloading, FFmpeg remuxing, acoustic fingerprinting, and offline library management run directly on your Android device.

---

## 📸 Key Features

### ⚡ 1. Media Downloader (GET Tab)
- **100% On-Device Extraction**: Link extraction is executed directly inside the app using an embedded Python 3.11 runtime (via Chaquopy) and cryptographically pinned `yt-dlp`.
- **Instant System Share-to-Download**: Share any video link from YouTube, Instagram, Facebook, X (Twitter), or Pinterest directly into SaveDuk via the Android system share sheet.
- **Background Foreground Service**: In-progress downloads continue reliably when the app is backgrounded or the screen is locked, complete with native ongoing progress notifications.
- **Lossless Stream Remuxer**: Merges high-definition video (AVC/MP4) and audio (AAC/M4A) streams locally using embedded FFmpeg without quality degradation or re-encoding overhead.
- **Direct Gallery Integration**: Automatically indexes completed downloads into the Android system media gallery (`Gal` native bridge).

### 🎵 2. SaveDuk Music (MUSIC Tab)
- **Ad-Free Music Streaming**: Search and stream full-length tracks with high-definition album art and zero advertisements.
- **Shazam-Grade Acoustic Recognition (ACRCloud)**: Identifies actual songs from background audio or video clips using acoustic waveform fingerprinting. Completely ignores noisy video titles, concert names, emojis, and compilation tags.
- **Playlist Import Engine**: Import playlists from **Spotify**, **YouTube Music**, or plain text tracklists. Automatically resolves every track to a playable stream with album artwork.
- **Offline Music Library**: Save any streamed track directly to device storage with zero compression loss. Tracks and storage usage (KB/MB) are monitored in real time.
- **Custom Playlists**: Create, manage, and delete custom playlists with instant search and one-tap playback.

### 🖤 3. Industrial Snappy UX & Customization
- **Snappy Haptic Feedback**: Tactile haptic responses engineered into every button, toggle, and gesture across the app.
- **Dynamic App Logo Theming**: Alternate between the classic **Psyduck Icon** and the neon **Music Waveform Icon** via Settings or by tapping the logo directly on the header!
- **Easter Egg About Screen**: Long-press the `SAVE//DUK` top bar header to reveal the built-in industrial About screen and architecture guide.
- **OTA Force Update Engine**: Built-in remote update checker (`version.json`) that can trigger seamless voluntary or mandatory (blocking) updates when you push new builds.

---

## 🏗️ Architecture & Pipeline

```
                              [User Action]
                                    │
                       ┌────────────┴───────────┐
                       │ Share Sheet / URL Input│
                       └────────────┬───────────┘
                                    │
                                    ▼
                          [UrlParserService]
             (Cleans tracking parameters: utm, igsh, fbclid, etc.)
                                    │
                     ┌──────────────┴──────────────┐
                     ▼                             ▼
             [Video Mode (GET)]           [Music Recognition]
                     │                             │
                     ▼                             ▼
         [Chaquopy Python 3.11]            [AcrCloudService]
             (Local yt-dlp)           (Acoustic Waveform Matching)
                     │                             │
                     ▼                             ▼
           [Extracted Streams]          [Exact Track & Artist]
                     │                             │
                     ▼                             ▼
            [DownloadService]             [YouTube Stream Sync]
          (Foreground Task)                        │
                     │                             ▼
                     ▼                    [MusicPlayerService]
            [MediaMuxerService]           (just_audio engine)
          (Local FFmpeg remuxing)
                     │
          ┌──────────┴──────────┐
          ▼                     ▼
    [Gal Gallery]       [SQLite Database]
(Saved to Android)    (Saveduk Offline DB)
```

---

## 🛠️ Tech Stack

| Component | Technology |
| :--- | :--- |
| **Framework** | [Flutter 3.x](https://flutter.dev) (Dart 3.x) |
| **Platform Target** | Android 7.0+ (minSdk 24, targetSdk 34+, Android 15 ready) |
| **On-Device Python** | [Chaquopy](https://chaquo.com/chaquopy/) (Python 3.11 embedded) |
| **Extraction Engine** | [`yt-dlp`](https://github.com/yt-dlp/yt-dlp) (Hash-pinned in `requirements.txt`) |
| **Acoustic Recognition** | [ACRCloud Audio Fingerprinting](https://www.acrcloud.com/) (HMAC-SHA1 API) |
| **Remuxing Engine** | [`ffmpeg_kit_flutter_new_min`](https://pub.dev/packages/ffmpeg_kit_flutter_new_min) |
| **Audio Playback** | [`just_audio`](https://pub.dev/packages/just_audio) |
| **Local Storage** | [`sqflite`](https://pub.dev/packages/sqflite) & [`path_provider`](https://pub.dev/packages/path_provider) |
| **Networking** | [`dio`](https://pub.dev/packages/dio) & [`crypto`](https://pub.dev/packages/crypto) |

---

## 🌐 Supported Platforms

| Platform | URL Formats Supported |
| :--- | :--- |
| **YouTube** | Videos (`youtube.com/watch?v=`), Shorts (`/shorts/`), Shortlinks (`youtu.be/`) |
| **Instagram** | Reels (`/reel/`, `/reels/`), Posts (`/p/`), Stories, Share Links (`/share/reel/`, `/share/p/`) |
| **Facebook** | Watch (`/watch`), Reels (`/reel/`, `/share/r/`), Videos (`fb.watch/`, `/share/v/`) |
| **X / Twitter** | Status media & video links (`x.com/*/status/*`, `twitter.com/*/status/*`) |
| **Pinterest** | Video pins & share links (`pinterest.com/pin/*`, `pin.it/*`) |
| **Spotify** | Track links (`open.spotify.com/track/*`) & Playlist links (`open.spotify.com/playlist/*`) |

---

## 🚀 Getting Started & Building

### Prerequisites
- **Flutter SDK**: `>= 3.11.4`
- **Android SDK**: Minimum API 24 (`minSdk = 24`), Target API 34+
- **Android NDK**: `28.2.13676358`
- **Java**: JDK 17

### Installation & Run

1. **Clone the repository**:
   ```bash
   git clone https://github.com/Vedk020/SaveDuk.git
   cd SaveDuk
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run on physical device**:
   ```bash
   flutter run
   ```

4. **Build release APK**:
   ```bash
   flutter build apk --release
   ```

---

## 🔄 Managing Over-The-Air (OTA) Updates

SaveDuk includes an embedded `UpdateService` that queries a remote JSON file to notify or force users to upgrade.

### How to push an update:
1. Edit the [`version.json`](version.json) file in your GitHub repository:
   ```json
   {
     "latest_version": "1.0.1",
     "latest_build": 2,
     "min_required_version": "1.0.0",
     "min_required_build": 1,
     "force_update": false,
     "title": "SaveDuk 1.0.1 Update",
     "release_notes": "• Improved acoustic music matching\n• Added snappy UI haptics\n• Battery optimizations",
     "download_url": "https://github.com/Vedk020/SaveDuk/releases/latest"
   }
   ```
2. Set `"force_update": true` if the update contains critical fixes that must be installed before opening the app.
3. SaveDuk checks this file on app launch and inside **Settings > Check for Updates**.

---

## 🔒 Security & Privacy Model

1. **No External Scraping Proxies**: Unlike web-based downloaders, SaveDuk connects directly from your device to the media host.
2. **Strict Android Isolation**:
   - `android:allowBackup="false"` prevents unauthorized data extraction via ADB backup.
   - `networkSecurityConfig` enforces HTTPS and blocks cleartext traffic.
   - Session cookies for Instagram/Facebook are stored with `0600` permissions and never leave your phone.
3. **No Dynamic Remote Code Execution**: Embedded Python wheels and FFmpeg binaries are compiled into the APK and verified against static hashes.

---

## 🔮 Recommended Features for Future Releases

1. **Synchronized Lyrics (LRC)**: Display real-time synchronized karaoke-style lyrics on the music playback screen.
2. **Audio Equalizer (EQ) & Bass Boost**: Built-in 5-band audio equalizer with presets (Rock, Pop, Bass Boost, Vocal).
3. **Sleep Timer**: Auto-pause audio playback after a user-defined duration (15m, 30m, 1h).
4. **Discord Rich Presence / Android Media Session Notification**: Full lockscreen media playback controls with notification scrubbing and Discord activity status.
5. **Batch Downloader**: Queue multiple links or an entire playlist to download concurrently into the gallery.

---

## 📄 License & Legal Notice

- SaveDuk utilizes LGPL-licensed binaries of FFmpeg through `ffmpeg_kit_flutter_new_min`.
- Only download and store content you own or have explicit rights to retain. Respect platform terms of service and creator rights.
