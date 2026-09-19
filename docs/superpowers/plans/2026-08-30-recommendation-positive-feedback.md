# Recommendation Positive Feedback Flutter Implementation Plan

> **For Worker Flow:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users activate and undo a Service-owned `感兴趣` signal from Home and the secondary recommendation screen without changing collections or the stable current list.

**Architecture:** Flutter parses the Service item feedback projection, exposes explicit repository operations, and lets `RecommendationController` update one item's projection only after server confirmation. Home and the secondary screen render the same semantic positive action with item-local pending state. Existing recommendation events trigger a daily read, never an automatic refresh.

**Tech Stack:** Flutter/Dart, shadcn_ui, Lucide icons, existing Service API/repository/controller patterns, flutter_test.

## Global Constraints

- Normative design: `/Volumes/ext/lx-music-server-web/docs/superpowers/specs/2026-08-30-recommendation-positive-feedback-design.md`.
- Start only after the Service plan at `/Volumes/ext/lx-music-server-web/docs/superpowers/plans/2026-08-30-recommendation-positive-feedback.md` passes its frozen verification.
- Preserve the dirty worktree and all unrelated user changes.
- Do not commit, push, deploy, alter collections, or regenerate unrelated goldens.
- Positive feedback never adds to `我喜欢`, playlists, downloads, or playback history.
- Activation/undo never calls the refresh endpoint or reorders/removes the current item.
- An omitted item feedback projection means inactive for compatibility with older Service versions.
- Ordinary feedback actions use Lucide; transport actions remain in `AppPlaybackGlyph`; every icon-only target is at least 44 px with Chinese semantics.

---

### Task 1: Adopt the Item Feedback Contract

**Files:**
- Modify: `lib/features/recommendations/recommendation_models.dart`
- Modify: `lib/features/recommendations/recommendation_repository.dart`
- Modify: `test/features/recommendations/recommendation_test_data.dart`
- Test: `test/features/recommendations/recommendation_repository_test.dart`

**Interfaces:**
- Consumes: Service item JSON `feedback: { interested: bool, interestedFeedbackId: String? }`.
- Produces: `RecommendationItemFeedback`, `RecommendationItem.feedback`, `RecommendationItem.copyWith(...)`.
- Produces: `RecommendationRepository.interestTrack(RecommendationItem)` and existing `undo(String)`.

- [ ] **Step 1: Establish current parsing and request evidence**

```sh
flutter test test/features/recommendations/recommendation_repository_test.dart
```

Expected: current daily, refresh, and negative feedback tests pass; no positive projection exists.

- [ ] **Step 2: Add defensive feedback parsing**

Implement:

```dart
final class RecommendationItemFeedback {
  const RecommendationItemFeedback({
    this.interested = false,
    this.interestedFeedbackId,
  });

  factory RecommendationItemFeedback.fromJson(Object? value) {
    if (value == null) return const RecommendationItemFeedback();
    final json = jsonObject(value, 'recommendation.item.feedback');
    final interested = json['interested'];
    if (interested is! bool) throw const ServiceException(
      'INVALID_RESPONSE',
      'Service response contains invalid recommendation feedback state.',
    );
    return RecommendationItemFeedback(
      interested: interested,
      interestedFeedbackId: json['interestedFeedbackId'] == null
          ? null
          : jsonString(json['interestedFeedbackId'], 'recommendation.item.feedback.id'),
    );
  }
}
```

Add it to `RecommendationItem`, serialize it into the display cache, and add a `copyWith(feedback:)` that preserves all other item fields.

- [ ] **Step 3: Add the repository operation**

```dart
Future<RecommendationFeedbackResult> interestTrack(
  RecommendationItem item,
) async => RecommendationFeedbackResult.fromJson(
  await api.request(
    'POST',
    '/api/v1/recommendations/feedback',
    body: {'type': 'interested_track', 'track': item.track.toJson()},
  ),
);
```

- [ ] **Step 4: Add focused contract coverage**

Update fixture data to include both active and inactive projections. Assert omitted projection becomes inactive, cache JSON round-trips active feedback ID, and the positive request contains the complete track with no playlist/download mutation call.

- [ ] **Step 5: Verify Task 1**

```sh
flutter test test/features/recommendations/recommendation_repository_test.dart
```

Expected: all tests pass.

### Task 2: Implement Confirmed Toggle State in the Controller

**Files:**
- Modify: `lib/features/recommendations/recommendation_controller.dart`
- Test: `test/features/recommendations/recommendation_controller_test.dart`

**Interfaces:**
- Consumes: `RecommendationRepository.interestTrack(item)` and `undo(feedbackId)`.
- Produces: `Future<bool> toggleInterest(RecommendationItem item)`.
- Produces: `RecommendationState.feedbackItemId` as the single item-local busy ID shared by positive and negative controls.

- [ ] **Step 1: Implement activation and undo**

```dart
Future<bool> toggleInterest(RecommendationItem item) async {
  if (state.feedbackItemId != null) return false;
  final previous = item.feedback;
  state = state.copyWith(feedbackItemId: item.id, clearError: true);
  _notify();
  try {
    final result = previous.interested && previous.interestedFeedbackId != null
        ? await repository.undo(previous.interestedFeedbackId!)
        : await repository.interestTrack(item);
    final active = result.active;
    await _replaceItemFeedback(
      item.id,
      RecommendationItemFeedback(
        interested: active,
        interestedFeedbackId: active ? result.id : null,
      ),
    );
    return true;
  } on Object catch (error) {
    state = state.copyWith(error: error, clearFeedbackItem: true);
    _notify();
    return false;
  }
}
```

When undo returns `{ active: false, type: 'undo' }`, clear the ID. Do not mutate state before server confirmation except for the busy marker.

- [ ] **Step 2: Centralize immutable item replacement**

Implement a private helper that replaces only the matching item in `DailyRecommendations.items`, clears the busy marker, notifies once, and writes the updated complete snapshot to `RecommendationCache`. Keep date, version, order, and item count unchanged.

- [ ] **Step 3: Preserve negative behavior and mutual pending state**

`dislikeTrack` and `dislikeArtist` keep their current removal behavior. All feedback methods reject a second action while `feedbackItemId` is set, ensuring the two controls cannot race for one or different items.

- [ ] **Step 4: Add controller coverage**

Assert activation waits for confirmation, sets the feedback ID without reordering, undo clears it, failures preserve the previous projection, cache follows confirmed state, and neither path calls daily refresh. Retain existing negative-removal tests.

- [ ] **Step 5: Verify Task 2**

```sh
flutter test test/features/recommendations/recommendation_controller_test.dart
```

Expected: all tests pass.

### Task 3: Add the Positive Action to Home Cards

**Files:**
- Modify: `lib/features/home/home_recommendation_section.dart`
- Test: `test/features/home/home_recommendation_section_test.dart`

**Interfaces:**
- Consumes: `RecommendationController.toggleInterest(item)` and `item.feedback.interested`.
- Produces: a 44 px `thumbsUp` action with `感兴趣` / `已感兴趣` tooltip and semantic state.

- [ ] **Step 1: Add the control without breaking card playback**

Extend `_RecommendationActions` with an `onInterest` callback. Use an ordinary `IconButton`:

```dart
IconButton(
  key: Key('home-recommendation-interest-${item.id}'),
  tooltip: item.feedback.interested ? '取消感兴趣' : '感兴趣',
  constraints: const BoxConstraints.tightFor(width: 44, height: 44),
  onPressed: busy ? null : onInterest,
  style: item.feedback.interested
      ? IconButton.styleFrom(
          backgroundColor: AppTokens.of(context).success.withValues(alpha: .14),
          foregroundColor: AppTokens.of(context).success,
        )
      : null,
  icon: busy
      ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
      : const Icon(LucideIcons.thumbsUp, size: 17),
)
```

Use the existing semantic positive/accent tokens if their exact names differ; do not introduce a color literal. Ensure tapping this nested button does not trigger the card playback gesture.

- [ ] **Step 2: Keep the responsive footer overflow-free**

Pass `busy: controller.state.feedbackItemId == item.id` to each card. Recalculate the narrow footer only if the additional 44 px action needs a second row; retain content-width-based 2/4/5 columns and `mainAxisExtent` behavior proven by the existing wide-shell regression.

- [ ] **Step 3: Add Home interaction coverage**

Assert inactive and active semantics/tooltips, confirmed highlight, undo, item-local disabling, no card removal, unchanged item count/order, and separate card-title playback. Run at 390, 900, 1300, plus the existing 1440-window/900-content constraint.

- [ ] **Step 4: Verify Task 3**

```sh
flutter test test/features/home/home_recommendation_section_test.dart test/features/home/home_screen_test.dart
```

Expected: all tests pass with no render overflow.

### Task 4: Add the Positive Action to the Secondary Recommendation Screen

**Files:**
- Modify: `lib/features/recommendations/recommendation_screen.dart`
- Test: `test/features/recommendations/recommendation_screen_test.dart`

**Interfaces:**
- Consumes: the same controller/item projection as Home.
- Produces: equivalent positive feedback affordance in `_RecommendationRow`.

- [ ] **Step 1: Add the row action**

Place `thumbsUp` before the existing `thumbsDown`, using the same key, tooltip, active styling, 44 px target, and busy rule as Home. Preserve the existing feedback bottom sheet for negative track/artist choices.

- [ ] **Step 2: Show bounded confirmation/error feedback**

After a successful toggle, show `已标记为感兴趣` or `已取消感兴趣`. If the controller returns false, retain the previous item state and let the screen's existing recommendation error notice report the Service failure.

- [ ] **Step 3: Add mobile and desktop coverage**

Assert activation and undo on 390×844 and 1200×900, no row overflow, no playback invocation from the nested positive action, and unchanged attributed playback from the transport button.

- [ ] **Step 4: Verify Task 4**

```sh
flutter test test/features/recommendations/recommendation_screen_test.dart
```

Expected: all tests pass.

### Task 5: Verify Invalidation and Freeze the Flutter Result

**Files:**
- Review: `lib/events/event_coordinator.dart`
- Test: `test/events/event_coordinator_test.dart` if recommendation invalidation coverage belongs there
- Review: all Flutter files changed in Tasks 1–4

**Interfaces:**
- Consumes: Service `recommendations.updated` event after activation/undo.
- Produces: one daily read through route/controller invalidation and zero automatic refresh calls.

- [ ] **Step 1: Confirm event behavior**

Add or extend the narrowest event/router test to assert `recommendations.updated` invalidates recommendation presentation once. The resulting controller load may call only `GET /api/v1/recommendations/daily`; it must not call `POST /daily/refresh`.

- [ ] **Step 2: Run the frozen focused suite**

```sh
flutter test \
  test/features/recommendations/recommendation_repository_test.dart \
  test/features/recommendations/recommendation_controller_test.dart \
  test/features/recommendations/recommendation_screen_test.dart \
  test/features/home/home_recommendation_section_test.dart \
  test/features/home/home_screen_test.dart \
  test/app/app_shell_test.dart \
  test/app/app_shell_routing_test.dart
```

Expected: zero failures.

- [ ] **Step 3: Analyze the changed Dart surface**

Run `flutter analyze` with the exact changed library and test paths. Expected: no issues.

- [ ] **Step 4: Enforce the icon system**

```sh
flutter test test/features/player/player_screen_test.dart test/design/app_components_test.dart
rg -n "LucideIcons\.(play|pause|skipBack|skipForward)" lib --glob '*.dart'
rg -n "(^|[^A-Za-z])Icons\.[A-Za-z0-9_]+" lib --glob '*.dart' -P
```

Expected: tests pass; the first `rg` has no matches; the second matches only `lib/design/components/app_playback_button.dart`.

- [ ] **Step 5: Build Flutter Web**

```sh
flutter build web --release
```

Expected: exit 0 and updated `build/web` output. Same-origin/Docker deployment remains outside this plan.

- [ ] **Step 6: Inspect the final diff**

```sh
git diff --check
git status --short
```

Expected: no whitespace errors. Preserve and separately report pre-existing UI changes, generated visual failures, Android artifacts, and other unrelated dirty-worktree entries.
