import 'dart:ui' show Size;

enum AppLayoutClass { mobile, narrow, desktop }

const double appTabletMinShortestSide = 600;
const double appExpandedSidebarMinWidth = 900;

AppLayoutClass classifyLayout(Size viewport) {
  if (viewport.shortestSide <= appTabletMinShortestSide) {
    return AppLayoutClass.mobile;
  }
  if (viewport.width < appExpandedSidebarMinWidth) {
    return AppLayoutClass.narrow;
  }
  return AppLayoutClass.desktop;
}

/// Compatibility adapter for the existing feature widgets during migration.
enum AppLayout { phone, tablet }

AppLayout appLayoutForSize(Size viewport) =>
    classifyLayout(viewport) == AppLayoutClass.mobile
    ? AppLayout.phone
    : AppLayout.tablet;
