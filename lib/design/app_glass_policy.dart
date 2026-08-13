import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

@immutable
final class AppGlassPolicy {
  const AppGlassPolicy({required this.blurEnabled, required this.reduceMotion});

  final bool blurEnabled;
  final bool reduceMotion;
}

final class AppGlassPerformanceController extends ChangeNotifier {
  static const sampleSize = 60;
  static const slowFrameThreshold = Duration(milliseconds: 24);
  static const slowFrameRatio = 0.2;

  final List<Duration> _frames = <Duration>[];
  bool _degraded = false;
  bool _started = false;

  bool get degraded => _degraded;

  void start() {
    if (_started) return;
    SchedulerBinding.instance.addTimingsCallback(_handleTimings);
    _started = true;
  }

  void stop() {
    if (!_started) return;
    SchedulerBinding.instance.removeTimingsCallback(_handleTimings);
    _started = false;
  }

  void _handleTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      recordFrame(timing.totalSpan);
    }
  }

  @visibleForTesting
  void recordFrame(Duration duration) {
    if (_degraded) return;
    _frames.add(duration);
    if (_frames.length > sampleSize) _frames.removeAt(0);
    if (_frames.length < sampleSize) return;
    final slow = _frames.where((frame) => frame > slowFrameThreshold).length;
    if (slow / sampleSize >= slowFrameRatio) {
      _degraded = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

final class AppGlassPolicyScope extends InheritedWidget {
  const AppGlassPolicyScope({
    required this.reduceTransparency,
    required this.performanceDegraded,
    required super.child,
    super.key,
  });

  final bool reduceTransparency;
  final bool performanceDegraded;

  static AppGlassPolicy policyOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppGlassPolicyScope>();
    final media = MediaQuery.maybeOf(context) ?? const MediaQueryData();
    final blurDisabled =
        (scope?.reduceTransparency ?? false) ||
        (scope?.performanceDegraded ?? false) ||
        media.highContrast;
    return AppGlassPolicy(
      blurEnabled: !blurDisabled,
      reduceMotion: media.disableAnimations || media.accessibleNavigation,
    );
  }

  @override
  bool updateShouldNotify(AppGlassPolicyScope oldWidget) =>
      reduceTransparency != oldWidget.reduceTransparency ||
      performanceDegraded != oldWidget.performanceDegraded;
}

final class AppGlassPolicyHost extends StatefulWidget {
  const AppGlassPolicyHost({
    required this.reduceTransparency,
    required this.child,
    super.key,
  });

  final bool reduceTransparency;
  final Widget child;

  @override
  State<AppGlassPolicyHost> createState() => _AppGlassPolicyHostState();
}

final class _AppGlassPolicyHostState extends State<AppGlassPolicyHost> {
  final AppGlassPerformanceController performance =
      AppGlassPerformanceController();

  @override
  void initState() {
    super.initState();
    performance.start();
  }

  @override
  void dispose() {
    performance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: performance,
    builder: (context, _) => AppGlassPolicyScope(
      reduceTransparency: widget.reduceTransparency,
      performanceDegraded: performance.degraded,
      child: widget.child,
    ),
  );
}
