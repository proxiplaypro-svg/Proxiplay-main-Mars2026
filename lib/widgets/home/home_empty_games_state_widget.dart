import '/components/list_empty_component_widget.dart';
import 'package:flutter/material.dart';

class HomeEmptyGamesState extends StatelessWidget {
  const HomeEmptyGamesState({
    super.key,
    required this.title,
    required this.description,
    this.height,
  });

  final String title;
  final String description;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final content = ListEmptyComponentWidget(
      title: title,
      description: description,
    );

    if (height == null) {
      return content;
    }

    return SizedBox(
      height: height,
      child: content,
    );
  }
}
