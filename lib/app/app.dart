import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:toastr_flutter/toastr.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/app_glass_policy.dart';
import '../design/app_theme.dart';
import '../design/app_theme_definition.dart';
import '../design/app_theme_scope.dart';
import '../design/components/app_feedback.dart';
import '../features/connection/connection_controller.dart';
import '../features/connection/network_type_monitor.dart';
import '../features/connection/connection_repository.dart';
import '../features/more/about_screen.dart';
import '../features/more/app_update.dart';
import '../features/more/github_update_checker.dart';
import '../features/player/service_audio_handler.dart';
import '../platform/macos_menu_bar.dart';
import '../l10n/app_localizations.dart';
import '../storage/app_image_cache.dart';
import '../storage/app_image_cache_scope.dart';
import '../storage/app_preferences.dart';
import '../storage/app_settings_controller.dart';
import '../storage/media_cache.dart';
import 'app_message_center.dart';
import 'app_providers.dart';
import 'app_router.dart';
import 'player_providers.dart';
import 'runtime_providers.dart';

final updateCheckerProvider = Provider<UpdateChecker>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return GitHubUpdateChecker(
    client: client,
    loadPackageInfo: PackageInfo.fromPlatform,
  );
});

final appPackageInfoLoaderProvider = Provider<AppPackageInfoLoader>(
  (_) =>
      () => PackageInfo.fromPlatform(),
);

final externalUriOpenerProvider = Provider<ExternalUriOpener>(
  (_) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

final _appRouterReadsProvider = Provider((ref) {
  return (
    connection: () => ref.read(connectionProvider),
    player: () => ref.read(playerControllerProvider),
    currentTrackActions: () => ref.read(currentTrackActionsProvider),
    keepAwake: () => ref.read(appSettingsProvider).value?.keepAwake ?? false,
    settings: () => ref.read(settingsControllerProvider),
  );
});

final _retiredAppRoutersProvider = Provider<_RetiredAppRouters>((ref) {
  final retired = _RetiredAppRouters();
  ref.onDispose(retired.dispose);
  return retired;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  final retired = ref.read(_retiredAppRoutersProvider);
  final invalidation = ref.read(eventInvalidationProvider);
  invalidation.addListener(refresh.trigger);
  ref.listen(
    connectionProvider.select(
      (connection) =>
          (hasError: connection.hasError, api: connection.value?.api),
    ),
    (previous, next) => refresh.trigger(),
  );
  ref.watch(currentTrackActionsProvider);
  final reads = ref.read(_appRouterReadsProvider);
  final router = buildAppRouter(
    readConnection: reads.connection,
    readPlayer: reads.player,
    readCurrentTrackActions: reads.currentTrackActions,
    readKeepAwake: reads.keepAwake,
    readSettings: reads.settings,
    readSourceVersion: () => invalidation.sourcesVersion,
    readPlaylistVersion: () => invalidation.playlistsVersion,
    readDownloadVersion: () => invalidation.downloadsVersion,
    readLibraryVersion: () => invalidation.libraryVersion,
    readPlaylistDetailVersion: invalidation.playlistDetailVersion,
    refreshListenable: refresh,
    disconnect: ref.read(connectionProvider.notifier).disconnect,
    updateChecker: ref.read(updateCheckerProvider),
    loadPackageInfo: ref.read(appPackageInfoLoaderProvider),
    openExternalUri: ref.read(externalUriOpenerProvider),
  );
  ref.onDispose(() {
    invalidation.removeListener(refresh.trigger);
    retired.add(router, refresh);
  });
  return router;
});

final class _RouterRefresh extends ChangeNotifier {
  void trigger() => notifyListeners();
}

final class _RetiredAppRouters {
  final List<(GoRouter, _RouterRefresh)> _entries = [];

  void add(GoRouter router, _RouterRefresh refresh) {
    _entries.add((router, refresh));
  }

  void dispose() {
    for (final (router, refresh) in _entries) {
      router.dispose();
      refresh.dispose();
    }
    _entries.clear();
  }
}

final class MusicFreeServiceApp extends StatefulWidget {
  MusicFreeServiceApp({
    super.key,
    ConnectionRepository? connectionRepository,
    AppPreferences? preferences,
    AudioPort? audio,
    this.mediaCache,
    this.imageCache,
    this.macOSMenuBar,
    this.networkTypeMonitor,
  }) : connectionRepository = connectionRepository ?? ConnectionRepository(),
       preferences = preferences ?? SharedAppPreferences(),
       audio = audio ?? SilentAudioPort();

  final ConnectionRepository connectionRepository;
  final AppPreferences preferences;
  final AudioPort audio;
  final MediaCache? mediaCache;
  final AppImageCache? imageCache;
  final MacOSMenuBarPort? macOSMenuBar;
  final NetworkTypeMonitor? networkTypeMonitor;

  @override
  State<MusicFreeServiceApp> createState() => _MusicFreeServiceAppState();
}

final class _MusicFreeServiceAppState extends State<MusicFreeServiceApp> {
  @override
  void dispose() {
    unawaited(widget.imageCache?.dispose());
    unawaited(widget.macOSMenuBar?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      connectionRepositoryProvider.overrideWithValue(
        widget.connectionRepository,
      ),
      appPreferencesProvider.overrideWithValue(widget.preferences),
      audioPortProvider.overrideWithValue(widget.audio),
      if (widget.mediaCache case final cache?)
        mediaCacheProvider.overrideWithValue(cache),
      if (widget.imageCache case final cache?)
        appImageCacheProvider.overrideWithValue(cache),
      if (widget.macOSMenuBar case final menuBar?)
        macOSMenuBarPortProvider.overrideWithValue(menuBar),
      if (widget.networkTypeMonitor case final monitor?)
        networkTypeMonitorProvider.overrideWithValue(monitor),
    ],
    child: const _AppView(),
  );
}

final class _AppView extends ConsumerWidget {
  const _AppView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(eventSubscriptionProvider);
    ref.watch(macOSMenuBarCoordinatorProvider);
    final AppSettings? settings = ref.watch(appSettingsProvider).value;
    final themeMode = settings?.themeMode ?? ThemeMode.system;
    final themeDefinition = AppThemeRegistry.definition(
      AppThemeRegistry.current,
    );
    final locale = switch (settings?.language ?? AppLanguage.system) {
      AppLanguage.system => null,
      AppLanguage.zh => const Locale('zh'),
      AppLanguage.en => const Locale('en'),
    };
    final router = ref.watch(appRouterProvider);
    final app = ShadApp.custom(
      theme: buildLightTheme(themeDefinition),
      darkTheme: buildDarkTheme(themeDefinition),
      themeMode: themeMode,
      appBuilder: (context) => MaterialApp.router(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        debugShowCheckedModeBanner: false,
        theme: buildAppMaterialTheme(Theme.of(context)),
        locale: locale,
        routerConfig: router,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalShadLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => Toastr.builder(
          context,
          AppThemeScope(
            definition: themeDefinition,
            child: AppGlassPolicyHost(
              reduceTransparency: settings?.reduceTransparency ?? false,
              child: ShadAppBuilder(child: _AppMessageHost(child: child!)),
            ),
          ),
        ),
      ),
    );
    final imageCache = ref.watch(appImageCacheProvider);
    Widget result = app;
    if (imageCache != null) {
      result = AppImageCacheScope(cache: imageCache, child: result);
    }
    return result;
  }
}

final class _AppMessageHost extends ConsumerStatefulWidget {
  const _AppMessageHost({required this.child});

  final Widget child;

  @override
  ConsumerState<_AppMessageHost> createState() => _AppMessageHostState();
}

final class _AppMessageHostState extends ConsumerState<_AppMessageHost> {
  StreamSubscription<AppMessage>? _subscription;

  @override
  void initState() {
    super.initState();
    final center = ref.read(appMessageCenterProvider);
    _subscription = center.messages.listen((message) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showAppMessage(
          context,
          title: message.title,
          message: message.message,
          destructive: true,
        );
      });
    });
    center.revealPending();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
