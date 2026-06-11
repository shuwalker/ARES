# ARES — Autonomous Reasoning & Execution System

**v0.1.0 — "Batteries Included, Pro Extensions Optional"**

ARES is a powerful, self-sufficient desktop AI application for macOS. It provides a beautiful Mission Control UI for interacting with your local or cloud agents.

---

## 🔋 Batteries Included (The Core)

ARES runs natively on macOS with zero external dependencies. The moment you drag it into the `/Applications` folder, it just works:

- **Native Brain:** On-device reasoning using `mlx-swift` (runs Llama 3 locally).
- **Native Perception:** Directly reads your screen using Apple's `ScreenCaptureKit`.
- **Native Voice:** Talks and listens using native macOS `AVSpeechSynthesizer` and `SFSpeechRecognizer`.
- **Native Memory:** A local SQLite database powered by SwiftData.

---

## 🎛️ The Mission Control Dashboard

ARES features a completely modular, native SwiftUI drag-and-drop dashboard:
- **Glassmorphism Design:** Beautiful `ultraThinMaterial` styling blending perfectly with macOS.
- **Thought Stream:** A live, Matrix-style terminal showing what ARES is thinking and executing in real-time.
- **System Metrics:** Live Swift Charts showing Tokens/Sec and Context Window Usage.
- **Inspector Sidebar:** Instantly swap between backends (Ollama, Hermes, MLX) or toggle features anywhere in the app.

---

## 🧩 Pro Extensions (Managed Node Architecture)

While ARES is fully capable natively, it can securely orchestrate massive external repositories (like `SAM` or `Open-Sora`) for advanced capabilities.

Instead of making you open a terminal to install dependencies, ARES includes a built-in **Extension Manager**:
1. Click **Pro Extensions** in the Inspector Sidebar.
2. Select a heavy computer vision or video generation node.
3. ARES silently runs `git clone`, creates a `python -m venv`, and installs the model weights in the background.
4. When you ask for a video, ARES silently spins up the external Python process, retrieves the video, and kills the process to save your Mac's battery.

---

## 🏗️ Building & Running

```bash
# Prerequisites: Swift 6.1+, macOS 14+

cd ~/GitHub/ARES
swift build          # 0 errors, clean compile
swift run ARES       # Launch the app
```

### Environment Configuration

Set `ARES_ENV` to select development or production mode:

```bash
# Development mode (uses Dummy implementations for unfinished features)
ARES_ENV=development swift run ARES

# Production mode (rejects dummies, requires real backends)
ARES_ENV=production swift run ARES
```

---

## 📜 Architecture Patterns

ARES uses a rigorous Protocol-Oriented architecture:
1. **One concern per contract.** (e.g. `VoiceEngine.swift`)
2. **Wiring layer owns concretions.** (`WiringBuilder.swift`)
3. **Dummy Fallbacks.** If a feature isn't implemented natively yet (like advanced mimicry), it falls back to a safe `DummyMimicry()` implementation rather than crashing.

---

## 📞 Support & Community

Built by Jenkins Robotics.
- **Architecture questions?** → Check out the `/docs` folder.
- **License?** → Private repo. All rights reserved.
