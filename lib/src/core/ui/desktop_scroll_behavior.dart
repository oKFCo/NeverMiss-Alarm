import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

class DesktopScrollBehavior extends MaterialScrollBehavior {
  const DesktopScrollBehavior();

  bool _isDesktopPlatform(TargetPlatform platform) {
    return platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS;
  }

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final isDesktop = _isDesktopPlatform(getPlatform(context));
    final width = MediaQuery.maybeSizeOf(context)?.width ?? double.infinity;
    final isCompactLayout = width < 720;
    if (!isDesktop || isCompactLayout) {
      return child;
    }
    final controller = details.controller;
    return Scrollbar(
      controller: controller,
      // `thumbVisibility: true` requires an attached ScrollController.
      thumbVisibility: controller != null,
      trackVisibility: controller != null,
      interactive: controller != null,
      thickness: 10,
      radius: const Radius.circular(10),
      child: child,
    );
  }

  @override
  Set<PointerDeviceKind> get dragDevices {
    return {
      ...super.dragDevices,
      PointerDeviceKind.mouse,
      PointerDeviceKind.trackpad,
      PointerDeviceKind.stylus,
      PointerDeviceKind.unknown,
    };
  }
}
