# Svid App

<p align="center">
  <img src="assets/images/logo.jpg" alt="Svid Logo" width="128" height="128" style="border-radius: 20px;">
</p>

<p align="center">
  <strong>High-performance download manager powered by Rust + Flutter</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#supported-platforms">Platforms</a> •
  <a href="#installation">Installation</a> •
  <a href="#development">Development</a> •
  <a href="#tech-stack">Tech Stack</a>
</p>

---

## ✨ Features

### 🚀 Core Download Engine
- **Multi-platform video download** - YouTube, TikTok, Instagram, Facebook, X (Twitter), Reddit, Pinterest
- **Smart quality selection** - Platform-specific preferences with manual override
- **Multi-URL batch downloads** - Queue multiple downloads simultaneously
- **Real-time progress tracking** - Live progress bars with ETA and speed indicators
- **Auto-paste URL detection** - Automatically detects URLs from clipboard

### 🎬 Built-in Media Player
- **Video player** with Picture-in-Picture (PiP) support
- **Audio player** with waveform visualization
- **Image viewer** with zoom and pan
- **Mini player** - Continue watching while browsing

### 🎨 Modern UI/UX
- **Glassmorphism design** - Beautiful frosted glass aesthetic
- **6-tab navigation** - Home, Downloads, Platform, Player, Settings
- **Dark mode** - Native dark theme support
- **Drag & drop** - Drop URLs directly into the app
- **Hover animations** - Smooth micro-interactions

### 🖥️ Desktop Integration
- **System tray** - Minimize to tray for background downloads
- **Keyboard shortcuts** - Quick actions with Cmd/Ctrl hotkeys
- **Window management** - Remember position, size, and maximized state
- **Native notifications** - Download complete alerts

### 🌍 Internationalization
- **Multi-language support** - English, Vietnamese
- **Easy localization** - Extensible translation system

### 🔐 Platform Authentication
- **WebView login** - Authenticate with platforms for private content
- **Secure cookie storage** - Encrypted credential management
- **Session persistence** - Stay logged in across app restarts

---

## 🖥️ Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| **macOS** | ✅ Supported | Apple Silicon & Intel |
| **Windows** | ✅ Supported | Windows 10/11 |
| **Linux** | ✅ Supported | x64 distributions |
| **Android** | 🚧 Planned | Future release |

---

## 📥 Installation

### Pre-built Releases

Download the latest release for your platform from the [Releases](https://github.com/mydinh-studio/svid-desktop/releases) page.

### Build from Source

#### Prerequisites

- **Flutter SDK** 3.29.3 or later
- **Rust** 1.70 or later (for native bridge)
- **Platform-specific dependencies:**
  - macOS: Xcode Command Line Tools
  - Windows: Visual Studio Build Tools
  - Linux: `clang`, `cmake`, `ninja-build`, `libgtk-3-dev`

#### Quick Setup (after cloning)

```bash
# Clone the repository
git clone https://github.com/mydinh-studio/svid-desktop.git
cd svid-desktop

# One-time dev setup: installs deps + generates Freezed/Riverpod/Drift code
chmod +x scripts/setup_dev.sh
./scripts/setup_dev.sh
```

> **Why is `setup_dev.sh` required?**
> Generated files (`*.g.dart`, `*.freezed.dart`) are excluded from git. Running
> `setup_dev.sh` regenerates them. Without this step, the analyzer will report
> ~500 errors on a fresh clone — this is expected and is not a source code issue.

#### Full Build Steps

```bash
# Build Rust bridge
cd native && cargo build --release && cd ..

# Run the app
flutter run -d macos  # or -d windows, -d linux
```

---

## 🛠️ Development

### Project Structure

```
svid/
├── lib/
│   ├── main.dart              # App entry point
│   ├── app.dart               # App configuration
│   ├── bridge/                # Rust FFI bindings
│   ├── core/                  # Shared infrastructure
│   │   ├── auth/              # Authentication system
│   │   ├── constants/         # App-wide constants
│   │   ├── database/          # Drift SQLite database
│   │   ├── errors/            # Error handling
│   │   ├── l10n/              # Localization
│   │   ├── logging/           # App logger
│   │   ├── navigation/        # Navigation scaffold
│   │   ├── network/           # HTTP client
│   │   ├── providers/         # Global providers
│   │   ├── services/          # Window, Keyboard, Tray, Notification
│   │   ├── theme/             # Theme & design system
│   │   ├── utils/             # Validators, formatters
│   │   └── widgets/           # Shared widgets
│   └── features/              # Feature modules
│       ├── downloads/         # Download management
│       ├── home/              # Home screen
│       ├── player/            # Media player
│       └── settings/          # App settings
├── native/                    # Rust crate
│   ├── src/
│   │   └── api/               # Rust API functions
│   └── Cargo.toml
├── assets/
│   ├── images/                # App images & logo
│   ├── icons/                 # SVG icons
│   └── translations/          # i18n JSON files
├── macos/                     # macOS platform code
├── windows/                   # Windows platform code
└── linux/                     # Linux platform code
```

### Useful Commands

```bash
# Run in debug mode
flutter run -d macos

# Run with verbose logging
flutter run -d macos --verbose

# Build release
flutter build macos --release

# Generate code
dart run build_runner build

# Watch mode for code generation
dart run build_runner watch

# Run tests
flutter test

# Analyze code
flutter analyze
```

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd/Ctrl + V` | Paste URL from clipboard |
| `Cmd/Ctrl + N` | New download |
| `Cmd/Ctrl + F` | Focus search |
| `Cmd/Ctrl + ,` | Open settings |
| `Cmd/Ctrl + W` | Close player / Hide window |
| `Cmd/Ctrl + Q` | Quit app |
| `Space` / `K` | Play/Pause (in player) |
| `←` / `→` | Seek backward/forward |
| `↑` / `↓` | Volume up/down |
| `F` | Toggle fullscreen |
| `M` | Toggle mute |
| `Esc` | Exit fullscreen / Close dialogs |

---

## 🔧 Tech Stack

### Frontend
| Technology | Purpose |
|------------|---------|
| **Flutter** 3.29.3 | Cross-platform UI framework |
| **Riverpod** | State management |
| **GoRouter** | Navigation |
| **Drift** | SQLite database |
| **MediaKit** | Video/Audio playback |
| **EasyLocalization** | Internationalization |

### Backend / Native
| Technology | Purpose |
|------------|---------|
| **Rust** | High-performance native code |
| **flutter_rust_bridge** | Dart-Rust FFI |
| **reqwest** | HTTP client |
| **tokio** | Async runtime |

### Desktop Integration
| Package | Purpose |
|---------|---------|
| **window_manager** | Window control |
| **hotkey_manager** | Global keyboard shortcuts |
| **tray_manager** | System tray |
| **local_notifier** | Desktop notifications |

---

## 📸 Screenshots

<!-- Add screenshots here -->
*Coming soon*

---

## 🗺️ Roadmap

- [ ] Android support
- [ ] Browser extension for one-click download
- [ ] Download scheduler
- [ ] Subtitle download & embedding
- [ ] Playlist support
- [ ] Download speed limiter
- [ ] Proxy support
- [ ] Auto-update system

---

## 🤝 Contributing

Contributions are welcome! Please read our contributing guidelines before submitting a PR.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- [yt-dlp](https://github.com/yt-dlp/yt-dlp) - Video download backend inspiration
- [Flutter](https://flutter.dev) - Amazing UI framework
- [Rust](https://rust-lang.org) - Performance and safety
- [MediaKit](https://github.com/media-kit/media-kit) - Media playback

---

<p align="center">
  Made with ❤️ by <a href="https://svid.app">Svid</a>
</p>
