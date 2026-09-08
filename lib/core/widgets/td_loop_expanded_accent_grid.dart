import 'package:flutter/material.dart';

import '../domain/accent_level.dart';
import '../domain/song.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_theme.dart';
import 'accent_level_display.dart';

/// Read-only visualization of all bars in a song, expanding loops.
///
/// Each row represents one bar as it will be played. Bars inside a loop
/// are repeated according to [SongLoop.repeatCount]. Each row displays a
/// label (e.g. "Bar 3" or "Bar 3 (x2)") followed by colored accent dots
/// derived from the applicable [SongBarBeatPattern].
class TDLoopExpandedAccentGrid extends StatelessWidget {
  const TDLoopExpandedAccentGrid({
    required this.song,
    super.key,
  });

  /// The song whose bars should be expanded and displayed.
  final Song song;

  @override
  Widget build(BuildContext context) {
    final expandedBars = _expandBars();

    if (expandedBars.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: AppSpacing.md),
        const Text(
          'EXPANDED VIEW',
          style: AppTextTheme.sectionLabel,
        ),
        const SizedBox(height: AppSpacing.sm),
        ...expandedBars.map(
          (bar) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: _ExpandedBarRow(bar: bar),
          ),
        ),
      ],
    );
  }

  List<_ExpandedBar> _expandBars() {
    final result = <_ExpandedBar>[];
    final sortedLoops = List.of(song.loops)
      ..sort((a, b) => a.startBar.compareTo(b.startBar));

    var barIndex = 1;

    while (barIndex <= song.endBar) {
      final loop = _loopStartingAt(sortedLoops, barIndex);

      if (loop != null) {
        for (var repeat = 1; repeat <= loop.repeatCount; repeat++) {
          for (var b = loop.startBar; b <= loop.endBar; b++) {
            final accents = _accentsForBar(b, repeat);
            result.add(
              _ExpandedBar(
                barIndex: b,
                repeatPass: loop.repeatCount > 1 ? repeat : null,
                totalRepeats: loop.repeatCount > 1 ? loop.repeatCount : null,
                accents: accents,
              ),
            );
          }
        }
        barIndex = loop.endBar + 1;
      } else {
        final accents = _accentsForBar(barIndex, null);
        result.add(
          _ExpandedBar(
            barIndex: barIndex,
            accents: accents,
          ),
        );
        barIndex++;
      }
    }

    return result;
  }

  /// Find a loop that starts at the given [barIndex].
  SongLoop? _loopStartingAt(List<SongLoop> sortedLoops, int barIndex) {
    for (final loop in sortedLoops) {
      if (loop.startBar == barIndex) {
        return loop;
      }
    }
    return null;
  }

  /// Get the accent pattern for a specific bar, optionally for a specific
  /// repeat pass. Falls back to the song's default beats-per-bar pattern.
  List<AccentLevel> _accentsForBar(int barIndex, int? repeatPass) {
    // Sort beat patterns by barIndex descending to find the most recent one
    // that applies at or before the given barIndex.
    final sorted = List.of(song.beatPatterns)
      ..sort((a, b) => a.barIndex.compareTo(b.barIndex));

    // First try to find a pass-specific pattern for this bar.
    if (repeatPass != null) {
      for (final pattern in sorted.reversed) {
        if (pattern.barIndex <= barIndex && pattern.repeatPass == repeatPass) {
          return pattern.accents;
        }
      }
    }

    // Fall back to a pattern without a repeatPass restriction.
    for (final pattern in sorted.reversed) {
      if (pattern.barIndex <= barIndex && pattern.repeatPass == null) {
        return pattern.accents;
      }
    }

    // Default: all normal accents matching beatsPerBar.
    return List.filled(song.beatsPerBar, AccentLevel.normal);
  }
}

/// Internal model for a single expanded bar row.
class _ExpandedBar {
  const _ExpandedBar({
    required this.barIndex,
    required this.accents,
    this.repeatPass,
    this.totalRepeats,
  });

  final int barIndex;
  final List<AccentLevel> accents;
  final int? repeatPass;
  final int? totalRepeats;
}

/// Renders a single expanded bar as a row: label + accent dots.
class _ExpandedBarRow extends StatelessWidget {
  const _ExpandedBarRow({required this.bar});

  final _ExpandedBar bar;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: _labelWidth,
          child: Text(
            _label,
            style: AppTextTheme.label.copyWith(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        ...bar.accents.map(
          (accent) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _AccentDot(accent: accent),
          ),
        ),
      ],
    );
  }

  static const _labelWidth = 80.0;

  String get _label {
    final barText = 'Bar ${bar.barIndex}';
    if (bar.repeatPass != null && bar.totalRepeats != null) {
      return '$barText (\u00D7${bar.repeatPass})';
    }
    return barText;
  }
}

/// Small colored circle representing a single beat's accent level.
class _AccentDot extends StatelessWidget {
  const _AccentDot({required this.accent});

  final AccentLevel accent;

  static const _dotSize = 14.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _dotSize,
      height: _dotSize,
      decoration: BoxDecoration(
        color: colorForAccentLevel(accent),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          shortLabelForAccentLevel(accent),
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
