import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../design/app_glass_policy.dart';
import '../design/app_theme.dart';
import '../design/app_theme_definition.dart';
import '../design/app_theme_scope.dart';
import '../design/components/app_feedback.dart';
import '../features/connection/connection_controller.dart';
import '../features/connection/connection_repository.dart';
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

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  ref.watch(
    connectionProvider.select((connection) => connection.asData?.value),
  );
  ref.listen(connectionProvider, (previous, next) => refresh.trigger());
  ref.watch(currentTrackActionsProvider);
  final invalidation = ref.read(eventInvalidationProvider);
  invalidation.addListener(refresh.trigger);
  final router = buildAppRouter(
    readConnection: () => ref.read(connectionProvider),
    readPlayer: () => ref.read(playerControllerProvider),
    readCurrentTrackActions: () => ref.read(currentTrackActionsProvider),
    readKeepAwake: () =>
        ref.read(appSettingsProvider).value?.keepAwake ?? false,
    readSettings: () => ref.read(settingsControllerProvider),
    readSourceVersion: () => invalidation.sourcesVersion,
    readPlaylistVersion: () => invalidation.playlistsVersion,
    readDownloadVersion: () => invalidation.downloadsVersion,
    readLibraryVersion: () => invalidation.libraryVersion,
    readPlaylistDetailVersion: invalidation.playlistDetailVersion,
    refreshListenable: refresh,
    disconnect: ref.read(connectionProvider.notifier).disconnect,
  );
  ref.onDispose(() {
    router.dispose();
    invalidation.removeListener(refresh.trigger);
    refresh.dispose();
  });
  return router;
});

final class _RouterRefresh extends ChangeNotifier {
  void trigger() => notifyListeners();
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
  }) : connectionRepository = connectionRepository ?? ConnectionRepository(),
       preferences = preferences ?? SharedAppPreferences(),
       audio = audio ?? SilentAudioPort();

  final ConnectionRepository connectionRepository;
  final AppPreferences preferences;
  final AudioPort audio;
  final MediaCache? mediaCache;
  final AppImageCache? imageCache;
  final MacOSMenuBarPort? macOSMenuBar;

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
    final app = ShadApp.custom(
      theme: buildLightTheme(themeDefinition),
      darkTheme: buildDarkTheme(themeDefinition),
      themeMode: themeMode,
      appBuilder: (context) => MaterialApp.router(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        debugShowCheckedModeBanner: false,
        theme: buildAppMaterialTheme(Theme.of(context)),
        locale: locale,
        routerConfig: ref.watch(appRouterProvider),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalShadLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => AppThemeScope(
          definition: themeDefinition,
          child: AppGlassPolicyHost(
            reduceTransparency: settings?.reduceTransparency ?? false,
            child: ShadAppBuilder(child: _AppMessageHost(child: child!)),
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
