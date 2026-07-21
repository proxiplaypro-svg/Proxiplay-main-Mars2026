List<T> mergePagedStreamItems<T>({
  required List<T> currentItems,
  required List<T> incomingItems,
  required String Function(T item) getId,
}) {
  if (incomingItems.isEmpty) {
    return currentItems;
  }

  if (currentItems.isEmpty) {
    return List<T>.from(incomingItems);
  }

  final items = List<T>.from(currentItems);
  final itemIndexes = <String, int>{
    for (final entry in items.asMap().entries) getId(entry.value): entry.key,
  };

  for (final item in incomingItems) {
    final id = getId(item);
    final index = itemIndexes[id];
    if (index == null) {
      itemIndexes[id] = items.length;
      items.add(item);
      continue;
    }
    items[index] = item;
  }

  return items;
}
