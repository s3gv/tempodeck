# Credits

TempoDeck bundles third-party assets covered by permissive licenses.

## Fonts

- **JetBrains Mono** — © JetBrains, licensed under
  [SIL Open Font License 1.1](https://scripts.sil.org/OFL). Used for numeric
  displays (BPM, timings). See
  [jetbrains.com/lp/mono](https://www.jetbrains.com/lp/mono/).
- **Outfit** — © The Outfit Project Authors, licensed under
  [SIL Open Font License 1.1](https://scripts.sil.org/OFL). Used as the
  primary UI typeface.

## Audio

All click kit samples in `assets/audio/click_kits/` (Tock, Blip, Drum Kit,
Hype, Metal Kit, Mighty Kit) were recorded and produced from scratch for
TempoDeck and are released under the same MIT license as the source code.

## Dependencies

Runtime and build dependencies are declared in [`pubspec.yaml`](pubspec.yaml)
and their transitive licenses can be reviewed with `flutter pub deps`. Notable
libraries include:

- [Riverpod](https://pub.dev/packages/flutter_riverpod) — state management
- [Drift](https://pub.dev/packages/drift) — SQLite ORM
- [go_router](https://pub.dev/packages/go_router) — declarative routing
- [flutter_soloud](https://pub.dev/packages/flutter_soloud) — audio engine
- [ffmpeg_kit_audio_flutter](https://pub.dev/packages/ffmpeg_kit_audio_flutter)
  — audio transcoding on mobile
