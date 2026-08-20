import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/app_error.dart';
import '../../api/service_origin.dart';
import '../../design/app_breakpoints.dart';
import '../../design/components/app_button.dart';
import '../../design/components/app_feedback.dart';
import '../../design/components/app_form.dart';
import '../../design/components/app_mobile_chrome.dart';
import '../../design/design_tokens.dart';
import '../connection/connection_repository.dart';
import 'settings_controller.dart';

final class ConnectionSettingsScreen extends StatefulWidget {
  const ConnectionSettingsScreen({
    super.key,
    required this.controller,
    this.onBack,
  });

  final SettingsController controller;
  final VoidCallback? onBack;

  @override
  State<ConnectionSettingsScreen> createState() =>
      _ConnectionSettingsScreenState();
}

final class _ConnectionSettingsScreenState
    extends State<ConnectionSettingsScreen> {
  final lan = TextEditingController();
  final external = TextEditingController();
  var _originsLoaded = false;
  String? lanError;
  String? externalError;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncOrigins);
    _syncOrigins();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.refreshServiceSettings());
    });
  }

  void _syncOrigins() {
    final origins = widget.controller.serviceAccessOrigins;
    if (_originsLoaded || origins == null) return;
    _originsLoaded = true;
    lan.text = origins.lanOrigin;
    external.text = origins.externalOrigin;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncOrigins);
    lan.dispose();
    external.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    String? validate(String value, {required bool required}) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return required ? '请输入地址' : null;
      try {
        ServiceOrigin.parse(trimmed);
        return null;
      } on Object {
        return '请输入有效的 HTTP(S) 地址';
      }
    }

    setState(() {
      lanError = validate(lan.text, required: false);
      externalError = validate(external.text, required: false);
    });
    if (lanError != null || externalError != null) {
      return;
    }
    try {
      await widget.controller.saveConnectionSettings(
        lanOrigin: lan.text,
        externalOrigin: external.text,
      );
      if (mounted) {
        showAppMessage(
          context,
          title: '连接设置已保存',
          message: '已检测可用地址，并保持 Service 连接。',
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      showAppMessage(
        context,
        title: '保存失败',
        message: appErrorMessage(error, fallback: '地址未通过检测，当前 Service 连接保持不变。'),
        destructive: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final mobile =
          classifyLayout(MediaQuery.sizeOf(context)) == AppLayoutClass.mobile;
      return ColoredBox(
        color: AppTokens.of(context).background,
        child: ListView(
          key: const Key('connection-settings-screen'),
          padding: EdgeInsets.fromLTRB(
            mobile ? 16 : 38,
            mobile ? 20 : 34,
            mobile ? 16 : 38,
            mobile ? 124 : 40,
          ),
          children: [
            AppMobilePageHeader(
              title: '连接设置',
              eyebrow: _connectionLabel(widget.controller.connection),
              onBack: mobile ? widget.onBack : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            ShadCard(
              padding: const EdgeInsets.all(18),
              radius: BorderRadius.circular(AppRadii.panel),
              title: const Text('Service 地址'),
              description: const Text('配置自动切换时使用的内网与外网地址。'),
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AddressField(
                      label: '内网访问地址',
                      description: '连接 Wi-Fi 或有线网络时优先尝试；留空表示不启用。',
                      fieldKey: const Key('connection-lan-origin'),
                      controller: lan,
                      placeholder: 'http://192.168.1.20:3124',
                      error: lanError,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _AddressField(
                      label: '外网访问地址',
                      description: '离开内网时优先尝试；留空表示不启用。',
                      fieldKey: const Key('connection-external-origin'),
                      controller: external,
                      placeholder: 'https://music.example.com',
                      error: externalError,
                    ),
                    if (widget.controller.connectionSettingsError
                        case final error?) ...[
                      const SizedBox(height: AppSpacing.md),
                      AppNotice.error(
                        title: '连接设置未生效',
                        message: appErrorMessage(
                          error,
                          fallback: '请检查地址与网络后重试。',
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    AppButton(
                      key: const Key('save-connection-settings'),
                      loading: widget.controller.connectionSettingsBusy,
                      onPressed: _save,
                      child: const Text('保存并检测'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

final class _AddressField extends StatelessWidget {
  const _AddressField({
    required this.label,
    required this.description,
    required this.fieldKey,
    required this.controller,
    required this.placeholder,
    this.error,
  });

  final String label;
  final String description;
  final Key fieldKey;
  final TextEditingController controller;
  final String placeholder;
  final String? error;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTypography.title),
      const SizedBox(height: 4),
      Text(
        description,
        style: AppTypography.metadata.copyWith(
          color: AppTokens.of(context).muted,
        ),
      ),
      const SizedBox(height: 8),
      AppTextField(
        key: fieldKey,
        controller: controller,
        placeholder: placeholder,
        keyboardType: TextInputType.url,
      ),
      if (error != null) ...[
        const SizedBox(height: 6),
        Text(
          error!,
          style: AppTypography.metadata.copyWith(
            color: AppTokens.of(context).danger,
          ),
        ),
      ],
    ],
  );
}

String _connectionLabel(ConnectionDiagnostics? diagnostics) {
  if (diagnostics == null || !diagnostics.connected) return 'Service 暂不可达';
  return switch (diagnostics.endpointRole) {
    EndpointRole.lan => '当前通过内网连接',
    EndpointRole.external => '当前通过外网连接',
    EndpointRole.bootstrap => '当前通过备用地址连接',
  };
}
