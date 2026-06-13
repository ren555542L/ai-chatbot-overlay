# AI Desktop Overlay Assistant

A Flutter Windows desktop AI assistant overlay that opens with a global shortcut and can explain copied text/code using Gemini API.

## Features

- Global shortcut overlay
- Ctrl + Space to show/hide
- Ctrl + Shift + Space to explain clipboard content
- Explain, Debug, Summarize, and Make Notes buttons
- Gemini API integration
- Markdown response rendering

## Run Locally

```bash
flutter pub get
flutter run -d windows --dart-define=GEMINI_API_KEY=YOUR_API_KEY_HERE

Build for Windows
flutter build windows --dart-define=GEMINI_API_KEY=YOUR_API_KEY_HERE
```
Tech Stack :-
 - Flutter Desktop
 - Dart
 - Gemini API
 - window_manager
 - hotkey_manager
 - flutter_markdown
