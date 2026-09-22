enum LyricFormat { local }

class Lyric {
  final List<LyricLine> lines;
  final LyricFormat source;
  final String? rawText;
  final bool isDuet; // TTML 对唱标记：同时存在 v1 和 v2

  const Lyric(
    this.lines, [
    this.source = LyricFormat.local,
    this.rawText,
    this.isDuet = false,
  ]);

  static const Lyric empty = Lyric([]);

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  bool get isWordByWord => lines.isNotEmpty && lines.first is SyncLyricLine;

  int get uniqueAgentCount {
    final agents = <String>{};
    for (final line in lines) {
      if (line is SyncLyricLine && (line.agent?.isNotEmpty == true)) {
        agents.add(line.agent!);
      }
    }
    return agents.length;
  }
}

class LyricLine {
  final Duration start;
  Duration length;
  String? translation;
  String? romanLyric;

  LyricLine(this.start, this.length, [this.translation]) : romanLyric = null;
}

class BackgroundVocal {
  final String text;
  final List<SyncLyricWord> words;
  final Duration start;
  final Duration end;
  String? translation;
  String? romanLyric;

  BackgroundVocal({
    required this.text,
    required this.words,
    required this.start,
    required this.end,
    this.translation,
    this.romanLyric,
  });
}

class SyncLyricLine extends LyricLine {
  final List<SyncLyricWord> words;
  String? agent;
  String? bgText;
  List<SyncLyricWord> bgWords = [];
  String? bgTranslation;
  Duration? bgStart;
  Duration? bgEnd;
  BackgroundVocal? bg;

  SyncLyricLine(
    super.start,
    super.length,
    this.words, [
    super.translation,
    String? romanLyric,
  ]) {
    this.romanLyric = romanLyric;
  }

  String get content => words.map((w) => w.content).join();
}

class SyncLyricWord {
  final Duration start;
  Duration length;
  String content;
  bool isMerged;

  SyncLyricWord(this.start, this.length, this.content) : isMerged = false;
}
