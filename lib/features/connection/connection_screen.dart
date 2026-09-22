import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/app_error.dart';
import '../../design/components/app_button.dart';
import '../../design/components/app_feedback.dart';
import '../../design/design_tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../storage/app_preferences.dart';
import '../../storage/app_settings_controller.dart';
import 'connection_controller.dart';

final class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

String defaultServiceOrigin(TargetPlatform platform) => kIsWeb
    ? Uri.base.origin
    : switch (platform) {
        TargetPlatform.android => 'http://10.0.2.2:3124',
        _ => 'http://127.0.0.1:3124',
      };

final class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  final formKey = GlobalKey<ShadFormState>();
  final origin = TextEditingController();
  bool _originEdited = false;
  bool _restoringPersistedOrigin = false;
  bool _manualConnectionStarted = false;
  String? _persistedOrigin;

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<AppSettings>>(appSettingsProvider, (
      previous,
      next,
    ) {
      final savedOrigin =
          next.value?.origin ?? (kIsWeb ? Uri.base.origin : null);
      if (savedOrigin == null || !mounted) return;
      if (!_originEdited && origin.text.isEmpty) {
        _restoringPersistedOrigin = true;
        origin.text = savedOrigin;
        _restoringPersistedOrigin = false;
      }
      if (_persistedOrigin != savedOrigin) {
        setState(() => _persistedOrigin = savedOrigin);
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    origin.dispose();
    super.dispose();
  }

  Future<void> connect() async {
    if (!formKey.currentState!.saveAndValidate()) return;
    if (!_manualConnectionStarted) {
      setState(() => _manualConnectionStarted = true);
    }
    await ref.read(connectionProvider.notifier).connect(origin.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final connection = ref.watch(connectionProvider);
    final error = connection.error;
    final connecting = connection.isLoading && !connection.hasError;
    final coldStartConnecting =
        connecting &&
        _persistedOrigin != null &&
        !_originEdited &&
        !_manualConnectionStarted;
    if (coldStartConnecting) {
      return _ColdStartConnectingView(
        origin: _persistedOrigin!,
        onCancel: ref.read(connectionProvider.notifier).cancelConnection,
      );
    }
    return Scaffold(
      key: const Key('connection-route'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _ConnectionPanel(
                child: ShadForm(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Image.asset(
                        'assets/branding/TuneFlow.png',
                        key: const Key('connection-brand-logo'),
                        width: 64,
                        height: 64,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(LucideIcons.audioLines, size: 64),
                      ),
                      const SizedBox(height: 16),
                      const Icon(LucideIcons.cloud, size: 40),
                      const SizedBox(height: 16),
                      Text(
                        strings.connectTitle,
                        style: ShadTheme.of(context).textTheme.h3,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '输入服务端地址，连接后开始聆听',
                        textAlign: TextAlign.center,
                        style: ShadTheme.of(context).textTheme.muted,
                      ),
                      const SizedBox(height: 24),
                      ShadInputFormField(
                        key: const Key('service-origin-field'),
                        id: 'origin',
                        controller: origin,
                        enabled: !connecting,
                        label: Text(strings.serviceOrigin),
                        placeholder: Text(
                          defaultServiceOrigin(defaultTargetPlatform),
                        ),
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) {
                          if (!_restoringPersistedOrigin) {
                            _originEdited = true;
                          }
                        },
                        validator: (value) =>
                            value.trim().isEmpty ? strings.serviceOrigin : null,
                        onSubmitted: connecting ? null : (_) => connect(),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '填写完整地址，可包含端口',
                        style: ShadTheme.of(context).textTheme.muted,
                      ),
                      const SizedBox(height: 12),
                      AppButton(
                        key: const Key('connect-button'),
                        loading: connecting,
                        onPressed: connecting ? null : connect,
                        leading: const Icon(LucideIcons.link),
                        expands: true,
                        child: Text(
                          connecting ? strings.connecting : strings.connect,
                        ),
                      ),
                      if (connecting) ...[
                        const SizedBox(height: 12),
                        const Text('正在连接服务端，请稍候', textAlign: TextAlign.center),
                        AppButton(
                          key: const Key('cancel-connection-button'),
                          variant: ShadButtonVariant.outline,
                          onPressed: ref
                              .read(connectionProvider.notifier)
                              .cancelConnection,
                          child: const Text('取消连接'),
                        ),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        AppNotice.error(
                          key: const Key('connection-error'),
                          title: '连接失败',
                          message: appErrorMessage(
                            error,
                            fallback: '无法连接到 Service，请检查地址后重试。',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _ColdStartConnectingView extends StatelessWidget {
  const _ColdStartConnectingView({
    required this.origin,
    required this.onCancel,
  });

  final String origin;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final textTheme = ShadTheme.of(context).textTheme;
    return Scaffold(
      key: const Key('cold-start-connecting-route'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _ConnectionPanel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/branding/TuneFlow.png',
                      key: const Key('cold-start-connecting-brand-logo'),
                      width: 64,
                      height: 64,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(LucideIcons.audioLines, size: 64),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      strings.connectingTitle,
                      style: textTheme.h3,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      origin,
                      style: textTheme.muted,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(height: 24),
                    AppButton(
                      key: const Key('cancel-connection-button'),
                      variant: ShadButtonVariant.outline,
                      onPressed: onCancel,
                      child: const Text('取消连接'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(AppRadii.panel),
      ),
      child: child,
    );
  }
}
