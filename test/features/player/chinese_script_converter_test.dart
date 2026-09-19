import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/features/player/chinese_script_converter.dart';

void main() {
  test('converts simplified characters and preserves unrelated text', () {
    expect(toTraditionalChinese('专业后台 Lyrics 123'), '專業後台 Lyrics 123');
    expect(toTraditionalChinese('[00:01.20]简体歌词'), '[00:01.20]簡體歌詞');
  });
}
