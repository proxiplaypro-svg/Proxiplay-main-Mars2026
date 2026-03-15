import '/components/list_empty_component_widget.dart';
import 'package:flutter/material.dart';

class EmptyLotsState extends StatelessWidget {
  const EmptyLotsState({super.key});

  @override
  Widget build(BuildContext context) {
    return const ListEmptyComponentWidget(
      title: 'Liste vide',
      description: 'Aucun lot',
    );
  }
}
