import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/app_localizations.dart';
import '../app_glass_policy.dart';
import '../app_theme_definition.dart';
import '../design_tokens.dart';
import 'app_glass_surface.dart';

@immutable
final class AppDestination {
  const AppDestination({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

final class AppDesktopNavigation extends StatelessWidget {
  const AppDesktopNavigation({
    super.key,
    required this.destinations,
    required this.selectedId,
    required this.onSelected,
    this.footer,
    this.compact = false,
  });

  final List<AppDestination> destinations;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final Widget? footer;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      key: const Key('desktop-navigation'),
      width: compact ? 84 : 208,
      decoration: BoxDecoration(color: tokens.surface),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 16,
            20,
            compact ? 12 : 16,
            16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Wordmark(compact: compact),
              if (compact)
                const SizedBox(height: AppSpacing.xl)
              else ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '浏览',
                    style: AppTypography.metadata.copyWith(
                      color: tokens.muted,
                      fontSize: 11,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              for (final destination in destinations) ...[
                _NavigationItem(
                  destination: destination,
                  selected: destination.id == selectedId,
                  onPressed: () => onSelected(destination.id),
                  compact: compact,
                ),
                const SizedBox(height: AppSpacing.xxs),
              ],
              const Spacer(),
              if (footer != null) footer!,
            ],
          ),
        ),
      ),
    );
  }
}

final class AppMobileNavigation extends StatelessWidget {
  const AppMobileNavigation({
    super.key,
    required this.destinations,
    required this.selectedId,
    required this.onSelected,
  });

  final List<AppDestination> destinations;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: AppGlassSurface(
        key: const Key('mobile-bottom-navigation'),
        role: AppGlassRole.nav,
        child: SizedBox(
          height: 64,
          child: Row(
            children: destinations
                .map(
                  (destination) => Expanded(
                    child: _MobileNavigationItem(
                      destination: destination,
                      selected: destination.id == selectedId,
                      onPressed: () => onSelected(destination.id),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );
  }
}

final class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Image.asset(
        'assets/branding/TuneFlow.png',
        key: const Key('brand-logo'),
        width: compact ? 28 : 30,
        height: compact ? 28 : 30,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) => Icon(
          LucideIcons.audioLines,
          size: compact ? 22 : 24,
          color: AppTokens.of(context).accent,
        ),
      ),
      if (!compact) ...[
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            AppLocalizations.of(context).appTitle,
            key: const Key('brand-wordmark'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.section,
          ),
        ),
      ],
    ],
  );
}

final class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.destination,
    required this.selected,
    required this.onPressed,
    required this.compact,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = compact
        ? Icon(destination.icon, size: 20)
        : Row(
            children: [
              SizedBox(
                key: ValueKey('desktop-destination-icon-${destination.id}'),
                width: 24,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(destination.icon, size: 19),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  destination.label,
                  key: ValueKey('desktop-destination-label-${destination.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
    return Tooltip(
      message: compact ? destination.label : '',
      child: ShadButton.raw(
        variant: selected
            ? ShadButtonVariant.secondary
            : ShadButtonVariant.ghost,
        height: 48,
        expands: !compact,
        padding: compact
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 12),
        onPressed: onPressed,
        child: content,
      ),
    );
  }
}

final class _MobileNavigationItem extends StatelessWidget {
  const _MobileNavigationItem({
    required this.destination,
    required this.selected,
    required this.onPressed,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final reduceMotion = AppGlassPolicyScope.policyOf(context).reduceMotion;
    final color = selected ? tokens.accent : tokens.muted;
    return Semantics(
      key: ValueKey('mobile-destination-${destination.id}'),
      button: true,
      selected: selected,
      label: destination.label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadii.compactCard),
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            constraints: const BoxConstraints(minHeight: 44),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: selected ? tokens.surfaceWarm : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.compactCard),
              border: selected ? Border.all(color: tokens.border) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(destination.icon, color: color, size: 20),
                const SizedBox(height: 3),
                Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.metadata.copyWith(
                    color: color,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
