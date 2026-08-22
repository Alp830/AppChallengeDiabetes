# diabetes

A new Flutter project.

## API key

Put your Gemini API key in `.env` (get one free at
https://aistudio.google.com/apikey):

```env
GEMINI_API_KEY=your_api_key_here
```

The Gemini key powers everything that calls a model, including fridge photo
recognition, which uses `gemini-3.1-pro-preview` (multimodal) to enumerate every food
item in a photo. The value also supports `--dart-define=GEMINI_API_KEY=...` as a
fallback. Note: `.env` is bundled as a Flutter asset, so a full re-run (not hot
reload) is needed after changing it.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
