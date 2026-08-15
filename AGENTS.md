# TuneFlow Project Rules

## Icon System

`design.md` is the visual source of truth. Keep icon choices consistent with
its interaction and motion rules.

### Design Rules

- Use Lucide for ordinary interface icons, including navigation, page actions,
  lists, menus, status actions, and non-transport player actions.
- Treat previous, play, pause, and next as one playback transport family. Use
  Material Rounded for all four glyphs; never mix Lucide and Material within a
  transport cluster.
- Keep play and pause glyphs solid. Filled playback actions use the semantic
  playback action background and foreground tokens; unfilled actions retain
  the ordinary neutral foreground.
- Preserve a minimum 44 px target for icon-only controls and provide a Chinese
  semantic label and tooltip.
- Do not introduce another icon library, Cupertino control glyphs, or bespoke
  control painters unless the existing Lucide and Material Rounded families
  cannot express the requirement and `design.md` records the exception.

### Code Rules

- Obtain ordinary UI glyphs from `LucideIcons` exported by `shadcn_ui`.
- Obtain playback transport glyphs only through `AppPlaybackIcons` or
  `AppPlaybackGlyph` in
  `lib/design/components/app_playback_button.dart`.
- Do not use `LucideIcons.play`, `LucideIcons.pause`, `LucideIcons.skipBack`, or
  `LucideIcons.skipForward` in application code.
- Do not use raw Material `Icons.*` glyphs outside the shared playback icon
  abstraction. If a new Material transport glyph is required, add its semantic
  name to `AppPlaybackIcons` and consume that name at call sites.
- Reuse semantic names such as `previous`, `play`, `pause`, and `next`; feature
  widgets must not select icon families independently.

### Verification

For icon-system changes, run the focused widget suites:

```sh
flutter test test/features/player/player_screen_test.dart
flutter test test/design/app_components_test.dart
```

Confirm that no disallowed Lucide transport glyph remains:

```sh
rg -n "LucideIcons\.(play|pause|skipBack|skipForward)" lib --glob '*.dart'
```

The command must return no matches. Also confirm that direct Material glyphs
remain confined to the shared playback abstraction:

```sh
rg -n "(^|[^A-Za-z])Icons\.[A-Za-z0-9_]+" lib --glob '*.dart' -P
```

Expected matches are only in
`lib/design/components/app_playback_button.dart`.
