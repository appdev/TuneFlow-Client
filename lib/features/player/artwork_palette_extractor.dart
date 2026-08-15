import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'artwork_palette.dart';

abstract interface class ArtworkPaletteDecoding {
  Future<ArtworkPalette> extract(
    Uint8List encodedBytes, {
    required String fallbackSeed,
    required Brightness brightness,
  });
}

final class ArtworkPaletteExtractor implements ArtworkPaletteDecoding {
  const ArtworkPaletteExtractor();

  static const sampleDimension = 24;

  @override
  Future<ArtworkPalette> extract(
    Uint8List encodedBytes, {
    required String fallbackSeed,
    required Brightness brightness,
  }) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(
        encodedBytes,
        targetWidth: sampleDimension,
        targetHeight: sampleDimension,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) {
        return fallbackArtworkPalette(fallbackSeed, brightness: brightness);
      }
      return extractRgba(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        width: image.width,
        height: image.height,
        fallbackSeed: fallbackSeed,
        brightness: brightness,
      );
    } on Object {
      return fallbackArtworkPalette(fallbackSeed, brightness: brightness);
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  ArtworkPalette extractRgba(
    Uint8List rgba, {
    required int width,
    required int height,
    required String fallbackSeed,
    required Brightness brightness,
  }) {
    if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
      return fallbackArtworkPalette(fallbackSeed, brightness: brightness);
    }
    final buckets = <int, _ColorBucket>{};
    var highestSaturation = 0.0;
    for (var offset = 0; offset + 3 < width * height * 4; offset += 4) {
      final alpha = rgba[offset + 3];
      if (alpha < 128) continue;
      final color = Color.fromARGB(
        alpha,
        rgba[offset],
        rgba[offset + 1],
        rgba[offset + 2],
      );
      final hsv = HSVColor.fromColor(color);
      highestSaturation = math.max(highestSaturation, hsv.saturation);
      final luminance = color.computeLuminance();
      final hueBucket = (hsv.hue / 15).floor().clamp(0, 23);
      final lightBucket = (luminance * 4).floor().clamp(0, 3);
      final key = hueBucket * 4 + lightBucket;
      final chromaWeight = .25 + hsv.saturation * .75;
      final middleLightWeight =
          1 - ((luminance - .5).abs() * 1.2).clamp(0.0, .72);
      final weight = chromaWeight * middleLightWeight;
      buckets.putIfAbsent(key, _ColorBucket.new).add(color, hsv, weight);
    }
    if (buckets.isEmpty || highestSaturation < .055) {
      return fallbackArtworkPalette(fallbackSeed, brightness: brightness);
    }
    final candidates = buckets.values.toList()
      ..sort((first, second) => second.weight.compareTo(first.weight));
    final dominant = candidates.first;
    final companion = _companionFor(dominant, candidates);
    final accent = candidates.reduce(
      (first, second) =>
          first.accentScore >= second.accentScore ? first : second,
    );
    final base = _backgroundColor(dominant.color, brightness);
    final secondary = _backgroundColor(companion.color, brightness);
    final vinyl = _vinylColor(accent.color, fallbackSeed);
    return ArtworkPalette(
      backgroundBase: base,
      backgroundCompanion: secondary,
      vinylAccent: vinyl,
      foreground: readableArtworkForeground(base, secondary),
    );
  }

  _ColorBucket _companionFor(
    _ColorBucket dominant,
    List<_ColorBucket> candidates,
  ) {
    _ColorBucket? best;
    var bestScore = 0.0;
    for (final candidate in candidates.skip(1)) {
      final separation = _hueDistance(dominant.hue, candidate.hue) / 180;
      final score = candidate.weight * (.3 + separation * .7);
      if (separation >= .12 && score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    if (best != null) return best;
    return _ColorBucket.derived(
      HSVColor.fromAHSV(
        1,
        (dominant.hue + 150) % 360,
        math.max(.16, dominant.saturation * .72),
        dominant.value,
      ).toColor(),
    );
  }

  Color _backgroundColor(Color color, Brightness brightness) {
    final hsv = HSVColor.fromColor(color);
    final dark = brightness == Brightness.dark;
    return hsv
        .withSaturation(
          hsv.saturation.clamp(dark ? .12 : .08, dark ? .38 : .30),
        )
        .withValue(hsv.value.clamp(dark ? .10 : .86, dark ? .22 : .96))
        .toColor();
  }

  Color _vinylColor(Color color, String seed) {
    var hsv = HSVColor.fromColor(color);
    if (hsv.saturation < .12) {
      hsv = HSVColor.fromColor(
        fallbackArtworkPalette(seed, brightness: Brightness.light).vinylAccent,
      );
    }
    return hsv
        .withSaturation(hsv.saturation.clamp(.48, .82))
        .withValue(hsv.value.clamp(.52, .88))
        .toColor();
  }
}

double _hueDistance(double first, double second) {
  final direct = (first - second).abs();
  return math.min(direct, 360 - direct);
}

final class _ColorBucket {
  _ColorBucket();

  factory _ColorBucket.derived(Color color) {
    final hsv = HSVColor.fromColor(color);
    return _ColorBucket()
      .._red = color.r
      .._green = color.g
      .._blue = color.b
      .._hue = hsv.hue
      .._saturation = hsv.saturation
      .._value = hsv.value
      ..weight = 1;
  }

  double _red = 0;
  double _green = 0;
  double _blue = 0;
  double _hue = 0;
  double _saturation = 0;
  double _value = 0;
  double weight = 0;

  void add(Color color, HSVColor hsv, double sampleWeight) {
    _red += color.r * sampleWeight;
    _green += color.g * sampleWeight;
    _blue += color.b * sampleWeight;
    _hue += hsv.hue * sampleWeight;
    _saturation += hsv.saturation * sampleWeight;
    _value += hsv.value * sampleWeight;
    weight += sampleWeight;
  }

  Color get color => Color.from(
    alpha: 1,
    red: _red / weight,
    green: _green / weight,
    blue: _blue / weight,
  );
  double get hue => _hue / weight;
  double get saturation => _saturation / weight;
  double get value => _value / weight;
  double get accentScore => weight * (.3 + saturation * .7);
}
