import 'package:flutter/material.dart';

/// Prefer an intact address, then a break at @. Keep an unusually long domain
/// on one horizontally scrollable line instead of splitting its final letters.
class WinnerEmailText extends StatelessWidget {
  const WinnerEmailText({super.key, required this.email, required this.style});
  final String email;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          double width(String value) {
            final painter = TextPainter(
              text: TextSpan(text: value, style: style),
              textDirection: TextDirection.ltr,
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final result = painter.width;
            painter.dispose();
            return result;
          }

          final at = email.lastIndexOf('@');
          final needsBreak = width(email) > constraints.maxWidth && at > 0;
          final display = needsBreak
              ? '${email.substring(0, at + 1)}\n${email.substring(at + 1)}'
              : email;
          final text = SelectableText(display,
              style: style, textDirection: TextDirection.ltr);
          if (needsBreak &&
              (width(email.substring(0, at + 1)) > constraints.maxWidth ||
                  width(email.substring(at + 1)) > constraints.maxWidth)) {
            return SingleChildScrollView(
                scrollDirection: Axis.horizontal, child: text);
          }
          return text;
        },
      );
}
