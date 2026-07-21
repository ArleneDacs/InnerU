import 'package:flutter/material.dart';

extension ResponsiveContext on BuildContext {
  Size get screenSize => MediaQuery.sizeOf(this);
  double get screenWidth => screenSize.width;
  double get screenHeight => screenSize.height;

  bool get isCompactWidth => screenWidth < 360;
  bool get isTabletWidth => screenWidth >= 700;
  bool get isDesktopWidth => screenWidth >= 1024;

  double responsiveWidth({
    double compact = 16,
    double regular = 20,
    double tablet = 28,
    double desktop = 36,
  }) {
    if (isDesktopWidth) return desktop;
    if (isTabletWidth) return tablet;
    if (isCompactWidth) return compact;
    return regular;
  }

  double responsiveFont(
    double size, {
    double min = 0.9,
    double max = 1.2,
  }) {
    final scale = (screenWidth / 390).clamp(min, max);
    return size * scale;
  }

  double responsiveValue(
    double value, {
    double min = 0.85,
    double max = 1.25,
  }) {
    final scale = (screenWidth / 390).clamp(min, max);
    return value * scale;
  }

  double get contentMaxWidth {
    if (isDesktopWidth) return 720;
    if (isTabletWidth) return 640;
    return screenWidth;
  }
}

class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    super.key,
    required this.child,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final horizontal = context.responsiveWidth();
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: padding ?? EdgeInsets.symmetric(horizontal: horizontal),
            child: child,
          ),
        ),
      ),
    );
  }
}
