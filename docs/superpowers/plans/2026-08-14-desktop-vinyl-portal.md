# Desktop Vinyl Portal Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the desktop player's window-edge-cropped record with the approved D “Vinyl Portal”: an intentional clipped portal with a read-only playback axis while preserving the existing lyrics, controls, mobile player, and playback behavior.

**Architecture:** Add a focused `DesktopVinylPortal` presentation component that composes the existing `DesktopVinylRecord`, a semantic-free portal clip, and a transform-driven progress marker. `DesktopPlayerStage` computes responsive portal bounds from the existing reading-column boundary and passes only current artwork and playback state; `PlayerController`, `VinylRecord`, lyrics, mobile layouts, and desktop controls remain unchanged.

**Tech Stack:** Flutter 3.47 / Dart 3.9, Material widgets, existing TuneFlow design tokens and `AppGlassPolicyScope`, `flutter_test` widget tests, existing high-fidelity golden gallery.

## Global Constraints

- Preserve the existing Mist Sea theme, player backdrop, right-side title/metadata/lyrics structure, bottom progress and controls, queue, quality controls, and all mobile player behavior.
- The portal clip must fully contain the center artwork and spindle; only outer vinyl grooves may be clipped.
- The vertical axis is read-only, excluded from semantics and focus order, and never replaces the bottom seek control.
- Rotation remains active only for `playing && processing == PlayerProcessing.ready`; reduced motion, buffering, pause, completion, and error keep the existing stop/resume behavior.
- The progress marker uses a transform, clamps progress to `0...1`, and stays at the start for zero or invalid duration.
- Verify dark and light desktop players at 1024×768 and 1440×960; do not update mobile goldens.
- Do not add packages or page-local raw colors; consume `AppTokens` and existing spacing/radius/shadow tokens.
- Preserve all unrelated dirty-worktree changes. Do not commit unless the user explicitly authorizes commits during execution.

## File Map

- Create `lib/features/player/desktop_vinyl_portal.dart`: portal clip, existing desktop record composition, normalized progress calculation, visual axis, and marker transform.
- Create `test/features/player/desktop_vinyl_portal_test.dart`: normalization, geometry, marker movement, semantics, and fallback-artwork component coverage.
- Modify `lib/features/player/desktop_player_stage.dart`: replace direct off-window `DesktopVinylRecord` positioning with responsive `DesktopVinylPortal` bounds and state inputs.
- Modify `test/features/player/player_screen_test.dart`: replace obsolete 25%-window-crop assertions with portal/lyrics separation assertions at desktop sizes; retain existing rotation and reduced-motion tests.
- Modify only the four desktop-player golden files under `test/visual/full_goldens/`: dark/light at 1024×768 and 1440×960.
- Reuse `lib/features/player/desktop_vinyl_record.dart` and `lib/features/player/vinyl_record.dart` unchanged.

---

### Task 1: Build the Vinyl Portal component from failing component tests

**Files:**
- Create: `test/features/player/desktop_vinyl_portal_test.dart`
- Create: `lib/features/player/desktop_vinyl_portal.dart`
- Read unchanged: `lib/features/player/desktop_vinyl_record.dart`
- Read unchanged: `lib/features/player/vinyl_record.dart`

**Interfaces:**
- Consumes: `AppArtworkSource`, TuneFlow `AppTokens`, existing `DesktopVinylRecord`, `Duration position`, `Duration duration`, and `bool rotating`.
- Produces:

```dart
double normalizedPlaybackProgress({
  required Duration position,
  required Duration duration,
});

final class DesktopVinylPortal extends StatelessWidget {
  const DesktopVinylPortal({
    super.key,
    required this.source,
    required this.seed,
    required this.semanticLabel,
    required this.rotating,
    required this.position,
    required this.duration,
  });

  final AppArtworkSource source;
  final String seed;
  final String semanticLabel;
  final bool rotating;
  final Duration position;
  final Duration duration;
}
```

- Stable keys: `player-desktop-vinyl-portal`, `player-desktop-vinyl-portal-clip`, `player-desktop-vinyl-progress-axis`, and `player-desktop-vinyl-progress-marker`.

- [ ] **Step 1: Write failing normalization and component tests**

Create `test/features/player/desktop_vinyl_portal_test.dart` with literal expectations independent of the implementation:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicfree_service_client/design/app_theme.dart';
import 'package:musicfree_service_client/design/components/artwork.dart';
import 'package:musicfree_service_client/features/player/desktop_vinyl_portal.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  test('normalized playback progress clamps invalid and out-of-range values', () {
    expect(
      normalizedPlaybackProgress(
        position: const Duration(seconds: 30),
        duration: const Duration(seconds: 60),
      ),
      .5,
    );
    expect(
      normalizedPlaybackProgress(
        position: const Duration(seconds: -1),
        duration: const Duration(seconds: 60),
      ),
      0,
    );
    expect(
      normalizedPlaybackProgress(
        position: const Duration(seconds: 70),
        duration: const Duration(seconds: 60),
      ),
      1,
    );
    expect(
      normalizedPlaybackProgress(
        position: const Duration(seconds: 1),
        duration: Duration.zero,
      ),
      0,
    );
  });

  testWidgets('portal keeps artwork and spindle inside its visible clip', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(680, 625);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ShadApp.custom(
        theme: buildDarkTheme(),
        appBuilder: (context) => const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 680,
              height: 625,
              child: DesktopVinylPortal(
                source: AppArtworkSource.fallback(
                  fallbackSeed: 'kw:portal',
                ),
                seed: 'kw:portal',
                semanticLabel: 'Portal封面',
                rotating: false,
                position: Duration(seconds: 30),
                duration: Duration(seconds: 60),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final clip = tester.getRect(
      find.byKey(const Key('player-desktop-vinyl-portal-clip')),
    );
    final artwork = tester.getRect(
      find.byKey(const Key('player-desktop-vinyl-artwork')),
    );
    final spindle = tester.getRect(
      find.byKey(const Key('player-desktop-vinyl-spindle')),
    );
    expect(clip.contains(artwork.topLeft), isTrue);
    expect(clip.contains(artwork.bottomRight), isTrue);
    expect(clip.contains(spindle.center), isTrue);
    expect(find.bySemanticsLabel('Portal封面'), findsOneWidget);
    expect(
      find.byKey(const Key('player-desktop-vinyl-progress-axis')),
      findsOneWidget,
    );
  });

  testWidgets('progress marker moves down without becoming interactive', (
    tester,
  ) async {
    Future<void> pumpAt(Duration position) => tester.pumpWidget(
      ShadApp.custom(
        theme: buildDarkTheme(),
        appBuilder: (context) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 680,
              height: 625,
              child: DesktopVinylPortal(
                source: const AppArtworkSource.fallback(
                  fallbackSeed: 'kw:marker',
                ),
                seed: 'kw:marker',
                semanticLabel: 'Marker封面',
                rotating: false,
                position: position,
                duration: const Duration(seconds: 100),
              ),
            ),
          ),
        ),
      ),
    );

    await pumpAt(const Duration(seconds: 25));
    await tester.pump();
    final first = tester.getCenter(
      find.byKey(const Key('player-desktop-vinyl-progress-marker')),
    );
    await pumpAt(const Duration(seconds: 75));
    await tester.pump();
    final second = tester.getCenter(
      find.byKey(const Key('player-desktop-vinyl-progress-marker')),
    );

    expect(second.dy, greaterThan(first.dy));
    final axis = find.byKey(
      const Key('player-desktop-vinyl-progress-axis'),
    );
    expect(
      find.descendant(of: axis, matching: find.byType(Slider)),
      findsNothing,
    );
    expect(
      find.descendant(of: axis, matching: find.byType(GestureDetector)),
      findsNothing,
    );
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('NOW PLAYING'), findsNothing);
    semantics.dispose();
  });
}
```

The mutation these tests catch is restoring a zero/overflowing progress ratio, moving the center label outside the clip, or accidentally making the decorative axis interactive.

- [ ] **Step 2: Run the component test and verify RED**

Run:

```bash
flutter test test/features/player/desktop_vinyl_portal_test.dart
```

Expected: compilation fails because `desktop_vinyl_portal.dart`, `DesktopVinylPortal`, and `normalizedPlaybackProgress` do not exist.

- [ ] **Step 3: Implement the minimal portal component**

Create `lib/features/player/desktop_vinyl_portal.dart`. Use the following geometry so the center art is inside the clip at both approved sizes:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/components/artwork.dart';
import '../../design/design_tokens.dart';
import 'desktop_vinyl_record.dart';

double normalizedPlaybackProgress({
  required Duration position,
  required Duration duration,
}) {
  if (duration <= Duration.zero) return 0;
  return (position.inMicroseconds / duration.inMicroseconds)
      .clamp(0.0, 1.0)
      .toDouble();
}

final class DesktopVinylPortal extends StatelessWidget {
  const DesktopVinylPortal({
    super.key,
    required this.source,
    required this.seed,
    required this.semanticLabel,
    required this.rotating,
    required this.position,
    required this.duration,
  });

  final AppArtworkSource source;
  final String seed;
  final String semanticLabel;
  final bool rotating;
  final Duration position;
  final Duration duration;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const axisWidth = 24.0;
      const axisInset = 32.0;
      const markerSize = 8.0;
      final portalWidth = math.max(0.0, constraints.maxWidth - axisWidth);
      final portalHeight = constraints.maxHeight;
      final discDiameter = math.min(
        portalHeight * 1.08,
        portalWidth * 1.22,
      );
      final discLeft = -discDiameter * .16;
      final progress = normalizedPlaybackProgress(
        position: position,
        duration: duration,
      );

      return SizedBox.expand(
        key: const Key('player-desktop-vinyl-portal'),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: portalWidth,
              child: ClipRRect(
                key: const Key('player-desktop-vinyl-portal-clip'),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(portalHeight / 2),
                  bottomLeft: Radius.circular(portalHeight / 2),
                  topRight: const Radius.circular(20),
                  bottomRight: const Radius.circular(20),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTokens.of(context).surface.withValues(alpha: .16),
                    border: Border.all(
                      color: AppTokens.of(context).foreground.withValues(
                        alpha: .10,
                      ),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: discLeft,
                        top: (portalHeight - discDiameter) / 2,
                        width: discDiameter,
                        height: discDiameter,
                        child: DesktopVinylRecord(
                          source: source,
                          seed: seed,
                          semanticLabel: semanticLabel,
                          rotating: rotating,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: axisInset,
              bottom: axisInset,
              width: axisWidth,
              child: ExcludeSemantics(
                child: _PlaybackAxis(
                  progress: progress,
                  markerSize: markerSize,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
```

Implement `_PlaybackAxis` in the same file with a token-colored one-pixel line, a vertically rotated `NOW PLAYING` label, and a keyed marker moved only through `Transform.translate`:

```dart
final class _PlaybackAxis extends StatelessWidget {
  const _PlaybackAxis({required this.progress, required this.markerSize});

  final double progress;
  final double markerSize;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final travel = math.max(0.0, constraints.maxHeight - markerSize);
      final tokens = AppTokens.of(context);
      final accent = tokens.accent;
      return Stack(
        key: const Key('player-desktop-vinyl-progress-axis'),
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            left: (constraints.maxWidth - 1) / 2,
            top: 0,
            bottom: 0,
            width: 1,
            child: ColoredBox(color: accent.withValues(alpha: .5)),
          ),
          Transform.translate(
            offset: Offset(0, travel * progress),
            child: Container(
              key: const Key('player-desktop-vinyl-progress-marker'),
              width: markerSize,
              height: markerSize,
              decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
            ),
          ),
          Positioned(
            right: 0,
            top: 16,
            child: RotatedBox(
              quarterTurns: 1,
              child: Text(
                'NOW PLAYING',
                style: AppTypography.metadata.copyWith(
                  color: tokens.foregroundSecondary,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
```

Do not introduce a raw text color.

- [ ] **Step 4: Run the component test and verify GREEN**

Run:

```bash
dart format lib/features/player/desktop_vinyl_portal.dart test/features/player/desktop_vinyl_portal_test.dart
flutter test test/features/player/desktop_vinyl_portal_test.dart
```

Expected: all tests pass, with no overflow or semantics exceptions.

- [ ] **Step 5: Commit only if explicit commit authorization exists**

```bash
git add lib/features/player/desktop_vinyl_portal.dart test/features/player/desktop_vinyl_portal_test.dart
git commit -m "feat: add desktop vinyl portal"
```

Without explicit authorization, leave the files unstaged and continue.

### Task 2: Integrate the portal into the responsive desktop stage

**Files:**
- Modify: `lib/features/player/desktop_player_stage.dart:1-126`
- Modify: `test/features/player/player_screen_test.dart:332-458`
- Test: `test/features/player/player_screen_test.dart`

**Interfaces:**
- Consumes: `DesktopVinylPortal` from Task 1 and existing `PlayerState.position`, `PlayerState.duration`, artwork, seed, semantic label, and rotation predicate.
- Produces: desktop stage geometry that keeps the portal right edge at least `AppSpacing.lg` before the reading column at 1024×768 and 1440×960.

- [ ] **Step 1: Replace the obsolete window-crop test with failing portal geometry tests**

Add `package:musicfree_service_client/design/design_tokens.dart` to the test imports. Rename the existing test `desktop player uses a cropped vinyl and fixes its left-aligned title above lyrics` to `desktop player contains the vinyl in a portal before the lyrics column` and replace the assertions for a 730px disc at `dx == -182.5` with:

```dart
final portal = find.byKey(const Key('player-desktop-vinyl-portal'));
final clip = find.byKey(const Key('player-desktop-vinyl-portal-clip'));
final artwork = find.byKey(const Key('player-desktop-vinyl-artwork'));
final spindle = find.byKey(const Key('player-desktop-vinyl-spindle'));
final title = find.byKey(const Key('player-desktop-track-title'));

expect(portal, findsOneWidget);
expect(clip, findsOneWidget);
expect(tester.getTopLeft(portal).dx, greaterThanOrEqualTo(0));
expect(
  tester.getRect(portal).right + AppSpacing.lg,
  lessThanOrEqualTo(tester.getRect(title).left),
);
expect(
  tester.getRect(clip).contains(tester.getRect(artwork).topLeft),
  isTrue,
);
expect(
  tester.getRect(clip).contains(tester.getRect(artwork).bottomRight),
  isTrue,
);
expect(tester.getRect(clip).contains(tester.getRect(spindle).center), isTrue);
expect(find.byKey(const Key('player-desktop-vinyl-progress-axis')), findsOneWidget);
```

Add a second run at `Size(1024, 768)` using the same literal invariants. Keep the existing assertions that title and lyrics share the same left edge and that scrolling lyrics does not move the title.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
flutter test test/features/player/player_screen_test.dart --plain-name "desktop player contains the vinyl in a portal before the lyrics column"
```

Expected: FAIL because `DesktopPlayerStage` still positions `DesktopVinylRecord` directly and no portal key is present.

- [ ] **Step 3: Replace direct record positioning with responsive portal bounds**

In `desktop_player_stage.dart`, replace the current `diameter` and negative 25% record offset with geometry derived from the reading-column boundary:

```dart
const portalWindowInset = 16.0;
final portalLeft = -horizontalStagePadding + portalWindowInset;
final portalAvailableWidth = math.max(
  0.0,
  readingLeft - portalLeft - AppSpacing.lg,
);
final portalWidth = math.min(680.0, portalAvailableWidth);
final portalHeight = math.min(
  math.max(0.0, constraints.maxHeight - 40),
  portalWidth * .92,
);
```

Replace the `DesktopVinylRecord` `Positioned` child with:

```dart
Positioned(
  left: portalLeft,
  top: (constraints.maxHeight - portalHeight) / 2,
  width: portalWidth,
  height: portalHeight,
  child: DesktopVinylPortal(
    source: artworkSource,
    seed: '${track.source}:${track.id}',
    semanticLabel: '${track.title}封面',
    rotating:
        state.playing && state.processing == PlayerProcessing.ready,
    position: state.position,
    duration: state.duration,
  ),
),
```

Import `desktop_vinyl_portal.dart` and remove the now-unused direct `desktop_vinyl_record.dart` import. Do not change reading-column, lyrics, metadata, backdrop, or control geometry.

- [ ] **Step 4: Run responsive stage, rotation, reduced-motion, and error tests**

Run:

```bash
dart format lib/features/player/desktop_player_stage.dart test/features/player/player_screen_test.dart
flutter test test/features/player/player_screen_test.dart --plain-name "desktop player contains the vinyl in a portal before the lyrics column"
flutter test test/features/player/player_screen_test.dart --plain-name "desktop vinyl rotates only while playback is ready"
flutter test test/features/player/player_screen_test.dart --plain-name "desktop vinyl stays still when reduced motion is enabled"
flutter test test/features/player/player_screen_test.dart --plain-name "desktop player replaces malformed lyrics with a local state"
```

Expected: all four commands pass. The unchanged rotation tests prove the portal did not alter `VinylRecord` pause/resume semantics.

- [ ] **Step 5: Commit only if explicit commit authorization exists**

```bash
git add lib/features/player/desktop_player_stage.dart test/features/player/player_screen_test.dart
git commit -m "feat: integrate vinyl portal into desktop player"
```

Without explicit authorization, leave the files unstaged and continue.

### Task 3: Freeze the approved visual output and run final integration verification

**Files:**
- Modify: `test/visual/full_goldens/desktop-player-1024x768.png`
- Modify: `test/visual/full_goldens/desktop-player-1024x768-light.png`
- Modify: `test/visual/full_goldens/desktop-player-1440x960.png`
- Modify: `test/visual/full_goldens/desktop-player-1440x960-light.png`
- Verify unchanged: all mobile player goldens and production files outside the Task 1–2 scope.

**Interfaces:**
- Consumes: final portal implementation and existing deterministic high-fidelity player fixture.
- Produces: four reviewed desktop-player baselines and a verified Flutter tree for the scoped change.

- [ ] **Step 1: Run desktop-player goldens before updating and verify expected RED**

Run each exact case so unrelated gallery pages do not participate:

```bash
flutter test test/visual/full_ui_gallery_test.dart --plain-name "desktop player dark 1440x960"
flutter test test/visual/full_ui_gallery_test.dart --plain-name "desktop player dark 1024x768"
flutter test test/visual/full_ui_gallery_test.dart --plain-name "desktop player light 1440x960"
flutter test test/visual/full_ui_gallery_test.dart --plain-name "desktop player light 1024x768"
```

Expected: each fails only with a golden pixel mismatch caused by the approved portal; any exception, overflow, missing font, missing image, or non-player diff is a defect to fix before baseline updates.

- [ ] **Step 2: Update only the four approved desktop-player baselines**

```bash
flutter test --update-goldens test/visual/full_ui_gallery_test.dart --plain-name "desktop player dark 1440x960"
flutter test --update-goldens test/visual/full_ui_gallery_test.dart --plain-name "desktop player dark 1024x768"
flutter test --update-goldens test/visual/full_ui_gallery_test.dart --plain-name "desktop player light 1440x960"
flutter test --update-goldens test/visual/full_ui_gallery_test.dart --plain-name "desktop player light 1024x768"
```

Inspect the four generated images. Accept only if the center artwork and spindle are fully visible, outer grooves are clipped by the portal, the axis is subordinate, and title/lyrics/bottom controls retain their existing geometry.

- [ ] **Step 3: Re-run the four goldens and focused player/component suites**

```bash
flutter test test/features/player/desktop_vinyl_portal_test.dart
flutter test test/features/player/desktop_vinyl_record_test.dart
flutter test test/features/player/player_screen_test.dart
flutter test test/visual/full_ui_gallery_test.dart --plain-name "desktop player dark 1440x960"
flutter test test/visual/full_ui_gallery_test.dart --plain-name "desktop player dark 1024x768"
flutter test test/visual/full_ui_gallery_test.dart --plain-name "desktop player light 1440x960"
flutter test test/visual/full_ui_gallery_test.dart --plain-name "desktop player light 1024x768"
```

Expected: every command exits 0 with zero failures.

- [ ] **Step 4: Run static checks and scope audit**

```bash
dart format --output=none --set-exit-if-changed lib/features/player/desktop_vinyl_portal.dart lib/features/player/desktop_player_stage.dart test/features/player/desktop_vinyl_portal_test.dart test/features/player/player_screen_test.dart
flutter analyze lib/features/player/desktop_vinyl_portal.dart lib/features/player/desktop_player_stage.dart test/features/player/desktop_vinyl_portal_test.dart test/features/player/player_screen_test.dart
git diff --check
git status --short
git diff --name-only
```

Expected: formatting, analysis, and diff checks exit 0. The implementation diff is limited to the files listed in this plan plus the already-existing user changes; no mobile golden, backdrop, controls, controller, dependency, or unrelated file is newly modified by this task.

- [ ] **Step 5: Commit only if explicit commit authorization exists**

```bash
git add lib/features/player/desktop_vinyl_portal.dart lib/features/player/desktop_player_stage.dart test/features/player/desktop_vinyl_portal_test.dart test/features/player/player_screen_test.dart test/visual/full_goldens/desktop-player-1024x768.png test/visual/full_goldens/desktop-player-1024x768-light.png test/visual/full_goldens/desktop-player-1440x960.png test/visual/full_goldens/desktop-player-1440x960-light.png docs/superpowers/specs/2026-08-14-desktop-vinyl-portal-design.md docs/superpowers/plans/2026-08-14-desktop-vinyl-portal.md
git commit -m "feat: add desktop vinyl portal"
```

Without explicit authorization, report the verified files as uncommitted and do not stage them.
