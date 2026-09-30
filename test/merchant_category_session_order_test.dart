import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/merchant_category_session_order.dart';

void main() {
  test('shuffle keeps every category exactly once', () {
    final categories = ['Alimentation', 'Restaurants', 'Beauté', 'Loisirs'];
    final shuffled = shuffledSessionCopy(categories, Random(7));

    expect(shuffled, containsAll(categories));
    expect(shuffled.toSet(), hasLength(categories.length));
  });

  test('shuffle keeps every merchant in its own category exactly once', () {
    final food = ['A', 'B', 'C', 'D'];
    final beauty = ['E', 'F'];
    final shuffledFood = shuffledSessionCopy(food, Random(4));
    final shuffledBeauty = shuffledSessionCopy(beauty, Random(4));

    expect(shuffledFood, containsAll(food));
    expect(shuffledFood.toSet(), hasLength(food.length));
    expect(shuffledBeauty, containsAll(beauty));
    expect(shuffledBeauty.toSet(), hasLength(beauty.length));
    expect(shuffledFood, isNot(contains('E')));
  });

  test('a retained session order survives filtering and clearing search', () {
    final sessionOrder = shuffledSessionCopy(['C', 'A', 'D', 'B'], Random(3));
    final initialSessionOrder = List<String>.of(sessionOrder);
    final filtered = sessionOrder
        .where((merchant) => ['A', 'B'].contains(merchant))
        .toList();

    expect(
        filtered,
        orderedEquals(
            sessionOrder.where((merchant) => ['A', 'B'].contains(merchant))));
    expect(sessionOrder, orderedEquals(initialSessionOrder));
  });

  test('new page sessions can use a different random sequence', () {
    final categories = ['A', 'B', 'C', 'D', 'E'];
    final firstSession = shuffledSessionCopy(categories, Random(1));
    final secondSession = shuffledSessionCopy(categories, Random(2));

    expect(firstSession, containsAll(categories));
    expect(secondSession, containsAll(categories));
    expect(firstSession, isNot(orderedEquals(secondSession)));
  });
}
