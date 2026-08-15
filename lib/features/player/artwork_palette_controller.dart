import 'dart:collection';
import 'dart:typed_data';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../design/components/artwork.dart';
import 'artwork_palette.dart';
import 'artwork_palette_extractor.dart';

typedef ArtworkBytesLoader =
    Future<Uint8List?> Function(AppArtworkSource source);

final class ArtworkPaletteController extends ChangeNotifier {
  ArtworkPaletteController({
    required ArtworkBytesLoader loadBytes,
    ArtworkPaletteDecoding decoder = const ArtworkPaletteExtractor(),
    int capacity = 48,
  }) : assert(capacity > 0),
       _loadBytes = loadBytes,
       _decoder = decoder,
       _capacity = capacity,
       _palette = fallbackArtworkPalette(
         'player',
         brightness: Brightness.light,
       );

  final ArtworkBytesLoader _loadBytes;
  final ArtworkPaletteDecoding _decoder;
  final int _capacity;
  final LinkedHashMap<String, ArtworkPalette> _cache = LinkedHashMap();

  ArtworkPalette _palette;
  ArtworkPalette get palette => _palette;

  var _generation = 0;
  String? _selectedKey;

  Future<void> select(
    AppArtworkSource source, {
    required Brightness brightness,
  }) async {
    final key = _keyFor(source, brightness);
    if (_selectedKey == key && _cache.containsKey(key)) return;
    _selectedKey = key;
    final generation = ++_generation;
    final cached = _takeCached(key);
    if (cached != null) {
      _publish(cached);
      return;
    }

    _publish(
      fallbackArtworkPalette(source.fallbackSeed, brightness: brightness),
    );
    Uint8List? bytes;
    try {
      bytes = await _loadBytes(source);
    } on Object {
      return;
    }
    if (bytes == null || generation != _generation || key != _selectedKey) {
      return;
    }
    ArtworkPalette extracted;
    try {
      extracted = await _decoder.extract(
        bytes,
        fallbackSeed: source.fallbackSeed,
        brightness: brightness,
      );
    } on Object {
      return;
    }
    if (generation != _generation || key != _selectedKey) return;
    _cache[key] = extracted;
    while (_cache.length > _capacity) {
      _cache.remove(_cache.keys.first);
    }
    _publish(extracted);
  }

  ArtworkPalette? _takeCached(String key) {
    final value = _cache.remove(key);
    if (value != null) _cache[key] = value;
    return value;
  }

  void _publish(ArtworkPalette next) {
    if (_palette == next) return;
    _palette = next;
    notifyListeners();
  }
}

String _keyFor(AppArtworkSource source, Brightness brightness) =>
    '${brightness.name}:${source.url ?? 'fallback:${source.fallbackSeed}'}';

Future<Uint8List?> loadArtworkBytes(
  BaseCacheManager manager,
  AppArtworkSource source,
) async {
  final url = source.url;
  if (url == null) return null;
  await for (final response in manager.getFileStream(
    url,
    key: url,
    headers: artworkRequestHeaders,
    withProgress: false,
  )) {
    if (response case FileInfo(:final file)) return file.readAsBytes();
  }
  return null;
}
