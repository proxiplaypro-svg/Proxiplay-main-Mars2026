import 'package:flutter/material.dart';

/// Keeps the merchant home content reachable when the keyboard reduces its height.
class MerchantHomeViewport extends StatelessWidget {
  const MerchantHomeViewport({super.key, required this.builder});

  final Widget Function(BuildContext context, double availableHeight) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: builder(context, constraints.maxHeight),
          ),
        ),
      );
}
