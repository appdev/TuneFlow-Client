<!-- Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4 -->

# TuneFlow Clear Download History Design

## Status

Approved interaction and architecture design. Awaiting implementation planning.

## Context

The Flutter download-management screen lists Service-owned download jobs and
currently supports only per-job actions. Users need one clear way to remove
finished history without interrupting active work or deleting downloaded music.

The Service is the source of truth for download records. Therefore, clearing
history must be a Service collection operation rather than a client-only filter
or a loop of unrelated per-item requests.

## Audience, job, and tone

- Audience: Chinese-speaking users managing music downloaded by a self-hosted
  TuneFlow Service.
- Primary job: remove obsolete finished download records in one deliberate
  action while keeping downloaded media and active tasks safe.
- Tone: refined, immersive, and crisp, within the existing Mist Sea Workbench
  design system.

## Goals

- Add a “清除下载记录” action to the download-management screen.
- Clear only jobs whose status is `completed` or `error`.
- Preserve completed audio and lyric files.
- Preserve jobs whose status is `waiting`, `running`, or `paused`.
- Clean temporary artifacts that belong to failed jobs.
- Use the shared adaptive modal presentation: bottom sheet on mobile and
  centered dialog on desktop and PC Web.
- Make the bulk mutation one Service operation with one result and one list
  publication.

## Non-goals

- Deleting downloaded music from the Service library.
- Cancelling, pausing, or deleting active download jobs.
- Clearing only the Flutter client's visible copy of Service records.
- Replacing the existing per-job action menu or delete action.
- Adding a new page-local modal implementation or visual theme.

## Interaction design

### Entry points

Desktop and PC Web place a secondary “清除记录” action in the download page
header alongside “全部暂停” and “刷新”. The action stays visually quieter than a
primary action and does not use a permanently filled danger surface.

Mobile places an icon-only clear-history action in the existing glass control
group at the right side of `AppMobilePageHeader`. It has a minimum 44 px target,
a “清除下载记录” semantic label, and a matching tooltip. The icon comes from the
existing Lucide family.

Both entry points are disabled when no job has status `completed` or `error`,
and while a clear request is already running.

### Confirmation

Both entry points call `AppBottomSheet.showDestructive`; callers do not branch
on platform or layout. The shared component presents a bottom sheet on mobile
and a centered dialog on desktop and PC Web.

- Title: “清除下载记录？”
- Message: “将清除 X 条已完成或失败记录。已下载的歌曲文件会保留，进行中的任务不受影响。”
- Cancel action: “取消”
- Confirm action: “清除”

The count is computed from the latest controller state immediately before the
modal opens. If the count is zero, no modal opens.

### Feedback and states

After confirmation, the page owns the asynchronous operation. The clear entry
enters a disabled/loading state so repeated submissions cannot occur. Records
remain visible until the Service confirms the mutation.

Success is silent: the refreshed list is the feedback. Failure preserves the
current list, restores the action, and presents “下载记录未清除，请重试” together
with the existing normalized Service error detail. A Service response indicating
that the endpoint is unavailable is translated to an instruction to upgrade the
Service.

The shared `AppButton`, mobile glass control, and adaptive modal retain their
existing hover, focus, pressed, disabled, loading, accessibility, and
reduced-motion behavior. This feature adds no page-private interaction styling.

## Service architecture

### API contract

Add the collection operation:

```text
DELETE /api/v1/downloads/history/records
```

Success returns HTTP 200:

```json
{
  "data": {
    "cleared": 2
  }
}
```

The operation is idempotent. When no eligible history exists, it returns
`cleared: 0`.

### Manager behavior

`DownloadManager.clearHistory()` selects only records in `completed` or
`error`. It never accepts a client-provided set of statuses, which keeps the
safety boundary inside the Service.

For completed records, the manager removes only the in-memory and database
records. It must not remove the final audio file, its lyric sidecar, or other
published resources.

For failed records, the manager removes any remaining part file and temporary
lyric sidecar using the same path-resolution and storage-root protections as
the existing per-record removal path. Active controllers are not aborted
because active statuses are never eligible.

Database record removal runs as one transaction. After the transaction
succeeds, the manager updates its in-memory map, publishes the new download
snapshot once, and returns the number of removed records. It does not pump the
queue because clearing terminal history does not free an active download slot.

If temporary-file cleanup fails before the transaction, the request fails and
the records remain. The implementation must not report success after only a
partial database mutation.

### Compatibility

The existing list, create, per-job action, and per-job delete routes remain
unchanged. Older clients continue to work. A newer Flutter client connected to
an older Service receives the explicit upgrade-required error described above.

## Flutter architecture

`DownloadRepository.clearHistory()` calls the new endpoint and parses the
returned `cleared` count.

`DownloadsController` exposes:

- the derived eligible history count;
- a `clearingHistory` state used to disable duplicate submissions;
- `clearHistory()`, which performs the repository mutation and refreshes the
  Service-owned list after success.

The controller keeps current jobs on failure and always releases
`clearingHistory`. The screen only invokes the controller and renders its state;
it does not assemble per-job delete requests.

Data flow:

```text
header action
  -> adaptive destructive confirmation
  -> DownloadsController.clearHistory()
  -> DownloadRepository.clearHistory()
  -> DELETE /api/v1/downloads/history/records
  -> Service transaction + one download publication
  -> Flutter refresh
  -> completed/error rows disappear; active rows remain
```

## Error handling

- No eligible records: entry disabled; Service remains idempotent with
  `cleared: 0`.
- Duplicate tap while clearing: ignored by disabled/controller state.
- Network or Service failure: keep the current snapshot, restore the action,
  and show a specific retry message.
- Unsupported endpoint: instruct the user to upgrade the Service.
- Temporary-file cleanup failure: no database records are removed and the
  Service returns an error.
- List refresh failure after a successful clear: the Service mutation remains
  authoritative; the controller marks the visible snapshot stale and lets the
  existing refresh/retry path recover it.

## Verification

### Service

- Manager test: clear `completed` and `error`, preserve `waiting`, `running`,
  and `paused`.
- Filesystem test: preserve completed audio and lyric files.
- Filesystem test: remove failed part and temporary lyric files.
- Failure test: a cleanup failure leaves database records intact.
- Publication test: one bulk clear emits one updated download snapshot.
- Route test: verify method, path, status, and `cleared` count.
- OpenAPI test: verify the collection-history operation and response schema.

### Flutter

- Repository test: verify `DELETE /api/v1/downloads/history/records` and response
  parsing.
- Controller test: verify eligible count, duplicate-request prevention,
  success refresh, and failure-state restoration.
- Desktop widget test: show the header action and centered confirmation dialog.
- Mobile widget test: show the 44 px semantic icon action and bottom
  confirmation sheet.
- Copy test: show the current eligible count and the file-preservation message.
- Disabled-state test: no eligible history means no actionable clear control.
- Mutation test: one confirmation sends one bulk request and leaves active rows
  visible after refresh.
- Failure test: preserve rows and show normalized retry or upgrade guidance.

Run focused Flutter analysis and download tests, plus the Service download
manager, route, and OpenAPI suites. Existing shared adaptive-modal tests remain
the source of truth for mobile-versus-desktop presentation behavior.

## Expected implementation scope

Flutter client:

- `lib/features/downloads/download_repository.dart`
- `lib/features/downloads/downloads_controller.dart`
- `lib/features/downloads/downloads_screen.dart`
- focused tests under `test/features/downloads/`

TuneFlow Service:

- `src/server/downloads/manager.ts`
- `src/server/routes/downloads.ts`
- `src/server/api/openapi.test.ts`
- focused download manager and route tests

No production files or components are deleted.
