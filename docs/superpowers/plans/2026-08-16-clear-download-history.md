# Clear Download History Implementation Plan

> **For agentic workers:** Use the global `workflow` skill's existing-plan execution entry. Review this plan against current evidence; when it is sound, enter execution directly. Only when material problems are found should `workflow` return to research, ideation, and planning to supplement this same plan before continuing. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one adaptive “清除下载记录” action that removes completed and failed Service download records while preserving downloaded media and active tasks.

**Architecture:** The Service owns a new idempotent bulk endpoint backed by one `DownloadManager.clearHistory()` operation and one download-list publication. Flutter calls that endpoint through `DownloadRepository`, coalesces duplicate requests in `DownloadsController`, and renders one shared action whose confirmation is automatically a mobile bottom sheet or desktop dialog.

**Tech Stack:** TypeScript 5.9, Fastify 5, TypeBox, better-sqlite3, Vitest 4, Flutter/Dart, shadcn_ui, existing `AppBottomSheet` and `AppButton` primitives.

## Global Constraints

- Clear only Service records whose status is exactly `completed` or `error`.
- Preserve completed audio, lyric sidecars, and all other published media resources.
- Preserve `waiting`, `running`, and `paused` records and never abort their controllers.
- Remove failed-job part files and temporary lyric sidecars through existing storage-root-safe path resolution.
- Mobile uses the shared bottom presentation; desktop and PC Web use the shared centered dialog. Callers never branch on platform or width.
- Use Lucide for the ordinary clear-history icon and keep the mobile target at least 44 px.
- Successful clearing is silent; failures preserve visible rows and provide retry or Service-upgrade guidance.
- Preserve unrelated dirty-worktree changes in both repositories.
- Do not add dependencies, delete production files, commit, push, or publish without separate user authorization.
- Authoritative design: `docs/superpowers/specs/2026-08-16-clear-download-history-design.md`.

---

### Task 1: Service-owned bulk history mutation

**Files:**
- Modify: `/Volumes/ext/lx-music-server-web/src/server/downloads/manager.ts`
- Test: `/Volumes/ext/lx-music-server-web/src/server/downloads/downloads.test.ts`

**Interfaces:**
- Consumes: existing `DownloadJobRecord`, `DownloadStatus`, `resolveRelative()`, `records`, `resolvedResources`, `db`, `publish()`, and `pump()` members.
- Produces: `DownloadManager.clearHistory(): number`, returning the count removed or throwing before database mutation when temporary cleanup fails.

- [x] **Step 1: Add a failing preservation-and-cleanup test**

Add a focused Vitest case that creates five jobs, assigns all five statuses, writes a completed final file plus an error part and part-lyric file, and captures publications:

```ts
it('clears completed and failed history while preserving media and active jobs', async() => {
  const root = createRoot()
  const publications: DownloadDto[][] = []
  const manager = new DownloadManager({
    storageRoot: root,
    autoStart: false,
    publish: jobs => publications.push(jobs),
    getSettings: () => ({
      'download.savePath': path.join(root, 'audio'),
      'download.maxDownloadNum': 1,
      'download.fileName': '歌名',
    } as TuneFlow.AppSetting),
    resolve: async() => ({ url: 'http://127.0.0.1/unused', headers: {} }),
    metadata: async() => {},
  })
  const completed = await manager.create({ musicInfo: fixtureTrack, quality: '128k' })
  const failed = await manager.create({ musicInfo: { ...fixtureTrack, id: 'failed' }, quality: '128k' })
  const waiting = await manager.create({ musicInfo: { ...fixtureTrack, id: 'waiting' }, quality: '128k' })
  const running = await manager.create({ musicInfo: { ...fixtureTrack, id: 'running' }, quality: '128k' })
  const paused = await manager.create({ musicInfo: { ...fixtureTrack, id: 'paused' }, quality: '128k' })
  manager.__setStateForTest(completed.id, 'completed')
  manager.__setStateForTest(failed.id, 'error')
  manager.__setStateForTest(running.id, 'running')
  manager.__setStateForTest(paused.id, 'paused')
  const finalPath = path.join(root, 'audio', completed.fileName)
  const partPath = path.join(root, 'tmp', `${failed.id}.part`)
  writeFileSync(finalPath, bytes)
  writeFileSync(partPath, bytes)
  writeFileSync(`${partPath}.lrc`, 'fixture')
  const publicationCount = publications.length

  expect(manager.clearHistory()).toBe(2)
  expect(manager.list().map(job => job.id).sort()).toEqual(
    [waiting.id, running.id, paused.id].sort(),
  )
  expect(existsSync(finalPath)).toBe(true)
  expect(existsSync(partPath)).toBe(false)
  expect(existsSync(`${partPath}.lrc`)).toBe(false)
  expect(publications).toHaveLength(publicationCount + 1)
  manager.close()
})
```

Import `DownloadDto` from `./types` if the publication array requires it.

- [x] **Step 2: Add a failing pre-transaction cleanup-error test**

Use a directory at the failed job's part path so `rmSync(..., { force: true })` rejects it without recursively deleting it:

```ts
it('keeps history records when failed-artifact cleanup cannot complete', async() => {
  const root = createRoot()
  const manager = new DownloadManager({
    storageRoot: root,
    autoStart: false,
    getSettings: () => ({
      'download.savePath': path.join(root, 'audio'),
      'download.maxDownloadNum': 1,
      'download.fileName': '歌名',
    } as TuneFlow.AppSetting),
    resolve: async() => ({ url: 'http://127.0.0.1/unused', headers: {} }),
    metadata: async() => {},
  })
  const failed = await manager.create({ musicInfo: fixtureTrack, quality: '128k' })
  manager.__setStateForTest(failed.id, 'error')
  mkdirSync(path.join(root, 'tmp', `${failed.id}.part`))

  expect(() => manager.clearHistory()).toThrow()
  expect(manager.get(failed.id)).toBeDefined()
  expect(getDB().prepare('SELECT id FROM web_downloads WHERE id = ?').get(failed.id))
    .toEqual({ id: failed.id })
  manager.close()
})
```

- [x] **Step 3: Run the focused tests and verify the intended failure**

Run:

```bash
cd /Volumes/ext/lx-music-server-web
npx vitest run src/server/downloads/downloads.test.ts -t "clears completed and failed history|keeps history records"
```

Expected: FAIL because `DownloadManager.clearHistory` is not defined.

- [x] **Step 4: Implement the minimal manager operation**

Add a synchronous collection method next to `removeCompletedForFile`:

```ts
clearHistory(): number {
  const history = [...this.records.values()].filter(record =>
    record.status === 'completed' || record.status === 'error',
  )
  if (history.length === 0) return 0

  for (const record of history) {
    if (record.status !== 'error') continue
    const part = this.resolveRelative(record.partRelativePath)
    rmSync(part, { force: true })
    rmSync(`${part}.lrc`, { force: true })
  }

  const remove = this.db.prepare('DELETE FROM web_downloads WHERE id = ?')
  this.db.transaction((records: DownloadJobRecord[]) => {
    for (const record of records) remove.run(record.id)
  })(history)
  for (const record of history) {
    this.records.delete(record.id)
    this.resolvedResources.delete(record.id)
  }
    this.publish()
    return history.length
}
```

Do not reuse `remove(id)` in a loop: it publishes and pumps per item and weakens the batch boundary.

- [x] **Step 5: Run the manager tests**

Run:

```bash
cd /Volumes/ext/lx-music-server-web
npx vitest run src/server/downloads/downloads.test.ts -t "clears completed and failed history|keeps history records"
```

Expected: both focused cases PASS.

- [x] **Step 6: Inspect the task diff**

Run `git diff --check -- src/server/downloads/manager.ts src/server/downloads/downloads.test.ts` from the Service root. Expected: no whitespace errors and no unrelated file changes included in this task.

---

### Task 2: Service route and OpenAPI contract

**Files:**
- Modify: `/Volumes/ext/lx-music-server-web/src/server/routes/downloads.ts`
- Modify: `/Volumes/ext/lx-music-server-web/src/server/app.test.ts`
- Modify: `/Volumes/ext/lx-music-server-web/src/server/api/openapi.test.ts`

**Interfaces:**
- Consumes: `DownloadManager.clearHistory(): number` from Task 1.
- Produces: `DELETE /api/v1/downloads/history/records -> { data: { cleared: number } }`, operation ID `clearDownloadHistory`.

- [x] **Step 1: Add a failing injected-route test**

In `src/server/app.test.ts`, create the normal test server and verify the empty-history idempotent response:

```ts
it('clears download history through one idempotent collection route', async() => {
  const { app } = await createTestServer()

  const response = await app.inject({
    method: 'DELETE',
    url: '/api/v1/downloads/history/records',
  })

  expect(response.statusCode).toBe(200)
  expect(response.json()).toEqual({ data: { cleared: 0 } })
})
```

- [x] **Step 2: Extend the failing OpenAPI assertions**

Add `'/api/v1/downloads/history/records'` to `expectedPaths`, then assert:

```ts
expect(document.paths['/api/v1/downloads/history/records'].delete.operationId)
  .toBe('clearDownloadHistory')
expect(successDataSchema('/api/v1/downloads/history/records', 'delete')).toMatchObject({
  type: 'object',
  required: ['cleared'],
  properties: { cleared: { type: 'integer', minimum: 0 } },
})
```

- [x] **Step 3: Run route and OpenAPI tests and verify failure**

Run:

```bash
cd /Volumes/ext/lx-music-server-web
npx vitest run src/server/app.test.ts src/server/api/openapi.test.ts -t "clears download history|documents the complete API"
```

Expected: FAIL because the route and OpenAPI path do not exist.

- [x] **Step 4: Register the static history route**

In `registerDownloadRoutes`, register this route before parameterized `:id` routes:

```ts
app.delete('/api/v1/downloads/history/records', {
  schema: {
    operationId: 'clearDownloadHistory',
    tags: ['Downloads'],
    summary: 'Clear completed and failed download history',
    response: {
      200: ApiSuccess(Type.Object({
        cleared: Type.Integer({ minimum: 0 }),
      })),
      ...ErrorResponses,
    },
  },
}, async() => ({ data: { cleared: manager.clearHistory() } }))
```

Keep `DELETE /api/v1/downloads/:id` unchanged.

- [x] **Step 5: Run the focused Service contract tests**

Run the same command from Step 3. Expected: both selected tests PASS.

- [x] **Step 6: Run Service lint on changed TypeScript files**

Run:

```bash
cd /Volumes/ext/lx-music-server-web
npx eslint src/server/downloads/manager.ts src/server/downloads/downloads.test.ts src/server/routes/downloads.ts src/server/app.test.ts src/server/api/openapi.test.ts
```

Expected: exit 0 with no lint findings.

---

### Task 3: Flutter repository and controller boundary

**Files:**
- Modify: `lib/features/downloads/download_repository.dart`
- Modify: `lib/features/downloads/downloads_controller.dart`
- Modify: `test/features/downloads/download_repository_test.dart`
- Modify: `test/features/downloads/downloads_controller_test.dart`

**Interfaces:**
- Consumes: `DELETE /api/v1/downloads/history/records` from Task 2 and existing JSON validation helpers.
- Produces: `DownloadRepository.clearHistory(): Future<int>`, `DownloadsController.clearableHistoryCount`, `DownloadsState.clearingHistory`, and coalesced `DownloadsController.clearHistory(): Future<int>`.

- [x] **Step 1: Add a failing repository contract test**

```dart
http.Response data(Object? value, [int status = 200]) =>
    http.Response(jsonEncode({'data': value}), status);

test('clears download history through the collection endpoint', () async {
  late http.Request captured;
  final repository = DownloadRepository(
    ServiceApi(
      ServiceOrigin.parse('http://service.local'),
      client: MockClient((request) async {
        captured = request;
        return data({'cleared': 2});
      }),
    ),
  );

  expect(await repository.clearHistory(), 2);
  expect(captured.method, 'DELETE');
  expect(captured.url.path, '/api/v1/downloads/history/records');
});
```

Reuse the helper for later repository response cases in the same file.

- [x] **Step 2: Add failing controller state and coalescing tests**

Cover the eligible count and one network mutation for two simultaneous callers:

```dart
test('clear history counts only completed and error jobs and coalesces requests', () async {
  final deleteResponse = Completer<http.Response>();
  var deleteCalls = 0;
  var cleared = false;
  final controller = DownloadsController(
    DownloadRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async {
          if (request.method == 'DELETE') {
            deleteCalls += 1;
            return deleteResponse.future;
          }
          return data(cleared
              ? [job('running', id: 'running')]
              : [
                  job('completed', id: 'completed'),
                  job('error', id: 'error'),
                  job('running', id: 'running'),
                ]);
        }),
      ),
    ),
  );
  await controller.refresh();
  expect(controller.clearableHistoryCount, 2);

  final first = controller.clearHistory();
  final second = controller.clearHistory();
  expect(controller.state.clearingHistory, isTrue);
  expect(deleteCalls, 1);
  cleared = true;
  deleteResponse.complete(data({'cleared': 2}));

  expect(await first, 2);
  expect(await second, 2);
  expect(controller.state.clearingHistory, isFalse);
  expect(controller.state.jobs.map((job) => job.id), ['running']);
});
```

Add a second test where DELETE returns an error and assert that jobs remain and `clearingHistory` returns to false.

- [x] **Step 3: Run focused Flutter tests and verify failure**

Run:

```bash
cd /Volumes/ext/MusicFree/flutter-client
flutter test test/features/downloads/download_repository_test.dart test/features/downloads/downloads_controller_test.dart
```

Expected: FAIL because the new repository/controller interfaces do not exist.

- [x] **Step 4: Implement repository response parsing**

```dart
Future<int> clearHistory() async {
  final json = jsonObject(
    await api.request('DELETE', '/api/v1/downloads/history/records'),
    'clearDownloadHistory',
  );
  return jsonInt(json['cleared'], 'clearDownloadHistory.cleared');
}
```

- [x] **Step 5: Implement controller state and request coalescing**

Add `clearingHistory` to `DownloadsState` and preserve it in every state reconstruction. Add:

```dart
Future<int>? _clearHistoryOperation;

int get clearableHistoryCount => state.jobs
    .where((job) =>
        job.status == DownloadStatus.completed ||
        job.status == DownloadStatus.error)
    .length;

Future<int> clearHistory() =>
    _clearHistoryOperation ??= _performClearHistory().whenComplete(() {
      _clearHistoryOperation = null;
    });

Future<int> _performClearHistory() async {
  state = DownloadsState(
    jobs: state.jobs,
    loading: state.loading,
    stale: state.stale,
    error: state.error,
    bytesPerSecond: state.bytesPerSecond,
    lastBulkResult: state.lastBulkResult,
    clearingHistory: true,
  );
  notifyListeners();
  try {
    final cleared = await repository.clearHistory();
    await refresh();
    return cleared;
  } finally {
    state = DownloadsState(
      jobs: state.jobs,
      loading: state.loading,
      stale: state.stale,
      error: state.error,
      bytesPerSecond: state.bytesPerSecond,
      lastBulkResult: state.lastBulkResult,
      clearingHistory: false,
    );
    notifyListeners();
  }
}
```

Ensure `refresh()` preserves `clearingHistory` while the request is active.

- [x] **Step 6: Run repository and controller tests**

Run the command from Step 3. Expected: all tests PASS.

- [x] **Step 7: Run focused Dart analysis**

Run:

```bash
flutter analyze lib/features/downloads/download_repository.dart lib/features/downloads/downloads_controller.dart test/features/downloads/download_repository_test.dart test/features/downloads/downloads_controller_test.dart
```

Expected: `No issues found!`.

---

### Task 4: Adaptive download-page action

**Files:**
- Modify: `lib/features/downloads/downloads_screen.dart`
- Modify: `test/features/downloads/downloads_screen_test.dart`

**Interfaces:**
- Consumes: `DownloadsController.clearableHistoryCount`, `DownloadsState.clearingHistory`, `DownloadsController.clearHistory()`, `AppBottomSheet.showDestructive`, `AppMobilePageHeader.actions`, and Lucide `listX`.
- Produces: keyed action `clear-download-history`, the approved Chinese confirmation copy, and layout-adaptive presentation without caller branching.

- [x] **Step 1: Add failing desktop and mobile presentation tests**

Create a shared mock whose GET response contains one completed, one error, and one running job:

```dart
Future<DownloadsController> historyController() async {
  final controller = DownloadsController(
    DownloadRepository(
      ServiceApi(
        ServiceOrigin.parse('http://service.local'),
        client: MockClient((request) async => http.Response(
          jsonEncode({
            'data': [job('completed'), job('error'), job('running')],
          }),
          200,
        )),
      ),
    ),
  );
  await controller.refresh();
  return controller;
}
```

For desktop:

```dart
testWidgets('desktop clears history through the centered confirmation', (tester) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = await historyController();
  await tester.pumpWidget(harness(DownloadsScreen(controller: controller)));

  await tester.tap(find.byKey(const Key('clear-download-history')));
  await tester.pumpAndSettle();

  expect(find.byType(ShadDialog), findsOneWidget);
  expect(find.text('清除下载记录？'), findsOneWidget);
  expect(find.textContaining('将清除 2 条'), findsOneWidget);
  expect(find.textContaining('已下载的歌曲文件会保留'), findsOneWidget);
});
```

For 390×844 mobile, tap the same key and assert `ShadDialog` is absent while `app-action-sheet-actions` is present. Inspect the `Semantics`/tooltip label and the icon button's minimum target.

- [x] **Step 2: Add failing disabled, mutation, and failure tests**

- With only `running`, `waiting`, and `paused`, assert the keyed action exists but its callback is null and tapping opens no modal.
- After confirming a two-record clear, assert exactly one DELETE request, completed/error rows disappear, and the running row remains.
- Return a 404 error envelope from DELETE and assert the rows remain plus “当前 Service 版本不支持清除记录，请更新 Service 后重试。” is shown.

- [x] **Step 3: Run screen tests and verify failure**

Run:

```bash
flutter test test/features/downloads/downloads_screen_test.dart
```

Expected: new cases FAIL because the action is absent.

- [x] **Step 4: Implement the confirmed action flow**

Add a screen method that captures the latest count, confirms through the shared adaptive component, and handles its own specific error copy:

```dart
Future<void> _clearHistory() async {
  final count = widget.controller.clearableHistoryCount;
  if (count == 0 || widget.controller.state.clearingHistory) return;
  final accepted = await AppBottomSheet.showDestructive(
    context,
    title: '清除下载记录？',
    message: '将清除 $count 条已完成或失败记录。已下载的歌曲文件会保留，进行中的任务不受影响。',
    confirmLabel: '清除',
  );
  if (!accepted || !mounted) return;
  try {
    await widget.controller.clearHistory();
  } on Object catch (error) {
    if (!mounted) return;
    final message = error is ServiceException && error.status == 404
        ? '当前 Service 版本不支持清除记录，请更新 Service 后重试。'
        : appErrorMessage(error, fallback: '下载记录未清除，请重试。');
    showAppMessage(
      context,
      title: '下载记录未清除',
      message: message,
      destructive: true,
    );
  }
}
```

Import `ServiceException`. Desktop inserts an `AppButton` using `ShadButtonVariant.ghost`, `LucideIcons.listX`, `loading: state.clearingHistory`, and the shared key. Mobile passes one `IconButton` through `AppMobilePageHeader.actions`, with the same key, tooltip/semantic label “清除下载记录”, 44 px minimum constraints, `LucideIcons.listX`, and a 16 px progress indicator while clearing.

Keep “全部暂停” and “刷新” behavior unchanged. Do not add a new modal widget or page-local colors.

- [x] **Step 5: Run the screen test suite**

Run the command from Step 3. Expected: all download-screen tests PASS.

- [x] **Step 6: Run focused UI analysis**

Run:

```bash
flutter analyze lib/features/downloads/downloads_screen.dart test/features/downloads/downloads_screen_test.dart
```

Expected: `No issues found!`.

---

### Task 5: Cross-boundary verification and frozen diff review

**Files:**
- Verify only; no planned production edits.

**Interfaces:**
- Consumes: all interfaces produced by Tasks 1–4.
- Produces: evidence that Service contract, Flutter data flow, adaptive presentation, formatting, and static analysis agree.

- [x] **Step 1: Format only changed source and test files**

Run `npx eslint ...` as in Task 2 for TypeScript validation; do not run a repository-wide fix command. Run:

```bash
cd /Volumes/ext/MusicFree/flutter-client
dart format \
  lib/features/downloads/download_repository.dart \
  lib/features/downloads/downloads_controller.dart \
  lib/features/downloads/downloads_screen.dart \
  test/features/downloads/download_repository_test.dart \
  test/features/downloads/downloads_controller_test.dart \
  test/features/downloads/downloads_screen_test.dart
```

- [x] **Step 2: Run the complete focused Service suites**

```bash
cd /Volumes/ext/lx-music-server-web
npx vitest run \
  src/server/downloads/downloads.test.ts \
  src/server/app.test.ts \
  src/server/api/openapi.test.ts
```

Expected: all tests in the three files PASS.

- [x] **Step 3: Run the complete focused Flutter suites**

```bash
cd /Volumes/ext/MusicFree/flutter-client
flutter test \
  test/features/downloads/download_repository_test.dart \
  test/features/downloads/downloads_controller_test.dart \
  test/features/downloads/downloads_screen_test.dart \
  test/design/app_bottom_sheet_test.dart
```

Expected: all focused tests PASS.

- [x] **Step 4: Run final focused analysis**

```bash
flutter analyze \
  lib/features/downloads/download_repository.dart \
  lib/features/downloads/downloads_controller.dart \
  lib/features/downloads/downloads_screen.dart \
  test/features/downloads/download_repository_test.dart \
  test/features/downloads/downloads_controller_test.dart \
  test/features/downloads/downloads_screen_test.dart
```

Expected: `No issues found!`.

- [x] **Step 5: Review final diffs without disturbing unrelated work**

From each repository root, run `git status --short`, then inspect only the files listed in this plan with `git diff -- <paths>`. Confirm:

- the Service endpoint never accepts caller-selected statuses;
- completed final media is never passed to `rmSync`;
- exactly one Service publication occurs per non-empty clear;
- clearing terminal history does not pump or restart the waiting queue;
- Flutter issues one collection DELETE and no per-row loop;
- the caller uses only `AppBottomSheet.showDestructive` for adaptive presentation;
- no unrelated dirty-worktree content was reverted or included.

- [x] **Step 6: Report evidence and residual runtime risk**

Report changed files, focused test counts/results, analysis/lint results, and whether Android or macOS runtime UI inspection was available. Do not claim device-level visual verification when no device was exercised.
