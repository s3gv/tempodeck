import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain/setlist.dart';
import '../../core/domain/song.dart';

/// Determines what the live view is playing.
///
/// Set by the calling screen before navigating to the live route.
/// The [LiveScreen] reads this to decide which mode to display.
sealed class LiveViewContext {
  const LiveViewContext();

  /// Title shown in the live view header.
  String get displayTitle;

  /// Mode label shown in the live view header.
  String get modeLabel;
}

/// Standalone metronome mode – no song or setlist context.
class MetronomeViewContext extends LiveViewContext {
  const MetronomeViewContext();

  @override
  String get displayTitle => 'Metronome';

  @override
  String get modeLabel => 'Metronome';
}

/// Song playback mode – live view follows song events, loops, tempo map.
class SongViewContext extends LiveViewContext {
  const SongViewContext({required this.song});

  final Song song;

  @override
  String get displayTitle => song.title;

  @override
  String get modeLabel => 'Song';
}

/// Setlist playback mode – live view follows setlist progression.
class SetlistViewContext extends LiveViewContext {
  const SetlistViewContext({required this.setlist});

  final Setlist setlist;

  @override
  String get displayTitle => setlist.title;

  @override
  String get modeLabel => 'Setlist';
}

/// Provides the current live view context.
///
/// Set by the calling screen (Metronome, SongEditor, SetlistEditor)
/// before navigating to the live route.
final liveViewContextProvider =
    NotifierProvider<LiveViewContextNotifier, LiveViewContext>(
  LiveViewContextNotifier.new,
);

class LiveViewContextNotifier extends Notifier<LiveViewContext> {
  @override
  LiveViewContext build() => const MetronomeViewContext();

  void set(LiveViewContext context) {
    state = context;
  }
}

/// Tracks the song currently open in the editor.
///
/// Updated by [SongEditorScreen] when a song is loaded. Read by the desktop
/// play button to set the correct [LiveViewContext] before navigation.
final activeEditorSongProvider = StateProvider<Song?>((ref) => null);

/// Tracks the setlist currently open in the editor.
///
/// Updated by [SetlistEditorScreen] when a setlist is loaded. Read by the
/// desktop play button to set the correct [LiveViewContext] before navigation.
final activeEditorSetlistProvider = StateProvider<Setlist?>((ref) => null);
