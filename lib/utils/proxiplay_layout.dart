import 'dart:math' as math;

import 'package:flutter/material.dart';

class ProxiPlayLayout {
  const ProxiPlayLayout._();

  static const double bottomNavContentHeight = 80.0;
  static const double minBottomSafeSpacing = 16.0;

  static double safeTopInset(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).top;

  static double safeBottomInset(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).bottom;

  static double keyboardInset(BuildContext context) =>
      MediaQuery.viewInsetsOf(context).bottom;

  static bool isKeyboardVisible(BuildContext context) =>
      keyboardInset(context) > 0.0;

  static double bottomNavHeight(
    BuildContext context, {
    double contentHeight = bottomNavContentHeight,
  }) {
    if (isKeyboardVisible(context)) {
      return 0.0;
    }
    return contentHeight + safeBottomInset(context);
  }

  static double bottomContentInset(
    BuildContext context, {
    double baseSpacing = minBottomSafeSpacing,
    bool includeKeyboard = true,
  }) {
    final safeBottom = math.max(safeBottomInset(context), baseSpacing);
    final keyboard = includeKeyboard ? keyboardInset(context) : 0.0;
    return safeBottom + keyboard;
  }

  static EdgeInsets bottomSheetPadding(
    BuildContext context, {
    double horizontal = 0.0,
    double top = 0.0,
    double bottomSpacing = minBottomSafeSpacing,
  }) {
    return EdgeInsets.fromLTRB(
      horizontal,
      top,
      horizontal,
      bottomContentInset(context, baseSpacing: bottomSpacing),
    );
  }
}
