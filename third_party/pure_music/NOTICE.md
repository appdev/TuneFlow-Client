# Pure-music source attribution

This migration incorporates and adapts code from Pure-music, local source
`/Users/evan/StudioProjects/Pure-music`, based on commit
`d130f724e8c2a8dc4c2d04e218840e6e2b758447` and its working tree on 2026-09-21.
The source project's GNU General Public License version 3 is preserved in
[LICENSE](LICENSE).

Directly adapted files:

- `lib/features/player/lyrics/lyric_document.dart` from `lib/lyric/lyric.dart`.
- `lib/features/player/lyrics/ttml_parser.dart` from `lib/lyric/ttml.dart`.
- `assets/shaders/soft_mesh_gradient.frag` from the source shader of the same name.

Related adaptations in the lyrics timeline, clock, rendering and mesh backdrop
integrate these features with TuneFlow's existing player, settings and API.
The staggered spring motion adapts
`lib/page/now_playing_page/component/lyric_stagger_motion.dart`.
The parser is modified to retain explicit timing and empty lines, avoid duplicate
nested paragraphs, and consume server-provided text without local file access.
