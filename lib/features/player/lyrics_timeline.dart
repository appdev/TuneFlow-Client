import '../../api/models.dart';
import 'lyrics/lyric_document.dart';
import 'lyrics/ttml_parser.dart';

final class TimedLyricWord {
  const TimedLyricWord(this.text, this.start, this.end);
  final String text;
  final Duration start;
  final Duration end;
  double progress(Duration position) => end <= start
      ? (position >= start ? 1 : 0)
      : ((position - start).inMicroseconds / (end - start).inMicroseconds)
            .clamp(0.0, 1.0);
}

final class TimedLyricLine {
  const TimedLyricLine({
    required this.time,
    required this.text,
    this.translation,
    this.romanization,
    this.end,
    this.words = const [],
    this.agent,
    this.background,
  });

  final Duration time;
  final String text;
  final String? translation;
  final String? romanization;
  final Duration? end;
  final List<TimedLyricWord> words;
  final String? agent;
  final TimedLyricLine? background;
}

List<TimedLyricLine> parseLyricsTimeline(Lyrics lyrics) {
  final rich = _parseRich(lyrics.verbatim ?? '');
  final originalRich = rich.isEmpty ? _parseRich(lyrics.original) : rich;
  final original = _parseLrc(
    lyrics.original.isNotEmpty ? lyrics.original : lyrics.verbatim ?? '',
  );
  final translated = _parseLrc(lyrics.translation ?? '');
  final romanized = _parseLrc(lyrics.romanization ?? '');
  if (originalRich.isNotEmpty) {
    return [
      for (final line in originalRich)
        TimedLyricLine(
          time: line.time,
          text: line.text,
          end: line.end,
          words: line.words,
          agent: line.agent,
          background: line.background,
          translation: _nearest(translated, line.time) ?? line.translation,
          romanization: _nearest(romanized, line.time) ?? line.romanization,
        ),
    ];
  }
  return original.entries
      .map(
        (entry) => TimedLyricLine(
          time: Duration(milliseconds: entry.key),
          text: entry.value,
          translation: _nearest(translated, Duration(milliseconds: entry.key)),
          romanization: _nearest(romanized, Duration(milliseconds: entry.key)),
        ),
      )
      .toList(growable: false);
}

String? _nearest(Map<int, String> lines, Duration time) {
  if (lines.containsKey(time.inMilliseconds)) return lines[time.inMilliseconds];
  MapEntry<int, String>? closest;
  var distance = 301;
  for (final entry in lines.entries) {
    final delta = (entry.key - time.inMilliseconds).abs();
    if (delta < distance) {
      closest = entry;
      distance = delta;
    }
  }
  return closest?.value;
}

List<TimedLyricLine> _parseRich(String text) {
  if (text.trimLeft().startsWith('<')) {
    final document = Ttml.fromTtmlText(text);
    if (document == null) return const [];
    List<TimedLyricWord> words(List<SyncLyricWord> source) => [
      for (final word in source)
        TimedLyricWord(word.content, word.start, word.start + word.length),
    ];
    return [
      for (final line in document.lines.whereType<SyncLyricLine>())
        TimedLyricLine(
          time: line.start,
          end: line.start + line.length,
          text: line.content,
          words: words(line.words),
          agent: line.agent,
          translation: line.translation,
          romanization: line.romanLyric,
          background: line.bg == null
              ? null
              : TimedLyricLine(
                  time: line.bg!.start,
                  end: line.bg!.end,
                  text: line.bg!.text,
                  words: words(line.bg!.words),
                  translation: line.bg!.translation,
                  romanization: line.bg!.romanLyric,
                ),
        ),
    ];
  }
  final stamp = RegExp(r'[\[<](\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?[\]>]');
  final offset = _lrcOffset(text);
  final result = <TimedLyricLine>[];
  var hasWords = false;
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final matches = stamp.allMatches(raw).toList();
    if (matches.isEmpty) continue;
    final enhanced = raw.contains('<');
    // 相邻的多个行时间标签表示重复歌词，不是逐字时间。
    final wordTimed =
        enhanced ||
        matches.asMap().entries.any(
          (entry) =>
              entry.key + 1 < matches.length &&
              raw
                  .substring(entry.value.end, matches[entry.key + 1].start)
                  .trim()
                  .isNotEmpty,
        );
    if (!wordTimed) {
      final content = raw.replaceAll(stamp, '').trim();
      for (final match in matches) {
        result.add(
          TimedLyricLine(time: _stampTime(match) - offset, text: content),
        );
      }
      continue;
    }
    final tokens = enhanced
        ? matches.where((m) => raw[m.start] == '<').toList()
        : matches;
    final words = <TimedLyricWord>[];
    for (var i = 0; i < tokens.length; i++) {
      final start = _stampTime(tokens[i]) - offset;
      final end = i + 1 < tokens.length
          ? _stampTime(tokens[i + 1]) - offset
          : start + const Duration(seconds: 1);
      final content = raw.substring(
        tokens[i].end,
        i + 1 < tokens.length ? tokens[i + 1].start : raw.length,
      );
      if (content.isEmpty) continue;
      if (end < start) return const [];
      words.add(TimedLyricWord(content, start, end));
    }
    if (words.isEmpty) continue;
    hasWords = true;
    result.add(
      TimedLyricLine(
        time: _stampTime(matches.first) - offset,
        text: words.map((w) => w.text).join(),
        words: words,
        end: words.last.end,
      ),
    );
  }
  if (!hasWords) return const [];
  result.sort((a, b) => a.time.compareTo(b.time));
  return result;
}

Duration _stampTime(RegExpMatch match) {
  final fraction = (match.group(3) ?? '0').padRight(3, '0');
  return Duration(
    minutes: int.parse(match.group(1)!),
    seconds: int.parse(match.group(2)!),
    milliseconds: int.parse(fraction),
  );
}

Duration _lrcOffset(String text) => Duration(
  milliseconds:
      int.tryParse(
        RegExp(
              r'\[offset:\s*(-?\d+)\]',
              caseSensitive: false,
            ).firstMatch(text)?.group(1) ??
            '',
      ) ??
      0,
);

Duration lyricTimelinePosition(Duration playbackPosition, Duration offset) {
  final value = playbackPosition - offset;
  return value.isNegative ? Duration.zero : value;
}

Duration lyricSeekPosition({
  required Duration lineTime,
  required Duration offset,
  required Duration duration,
}) {
  var value = lineTime + offset;
  if (value.isNegative) value = Duration.zero;
  if (duration > Duration.zero && value > duration) return duration;
  return value;
}

int activeLyricIndex(List<TimedLyricLine> lines, Duration position) {
  var low = 0;
  var high = lines.length - 1;
  var result = -1;
  while (low <= high) {
    final middle = low + ((high - low) >> 1);
    if (lines[middle].time <= position) {
      result = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return result;
}

Map<int, String> _parseLrc(String source) {
  final result = <int, String>{};
  final offset = _lrcOffset(source).inMilliseconds;
  final timestamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
  for (final rawLine in source.split(RegExp(r'\r?\n'))) {
    final matches = timestamp.allMatches(rawLine).toList(growable: false);
    if (matches.isEmpty) continue;
    final text = rawLine.replaceAll(timestamp, '').trim();
    for (final match in matches) {
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final fraction = match.group(3) ?? '0';
      final milliseconds = switch (fraction.length) {
        1 => int.parse(fraction) * 100,
        2 => int.parse(fraction) * 10,
        _ => int.parse(fraction.padRight(3, '0').substring(0, 3)),
      };
      final key = (minutes * 60 + seconds) * 1000 + milliseconds - offset;
      if (text.isNotEmpty || !result.containsKey(key)) result[key] = text;
    }
  }
  return Map.fromEntries(
    result.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}
