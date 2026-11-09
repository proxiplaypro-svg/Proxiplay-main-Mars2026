import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('merchant detail carousel keeps paging and has no full-screen tap', () {
    final source = File(
      'lib/pages/joueur/enseigne_detail_joueur_page/'
      'enseigne_detail_joueur_page_widget.dart',
    ).readAsStringSync();
    final start = source.indexOf(
        'PageView.builder(', source.indexOf('if (images.isEmpty)'));
    final end = source.indexOf('if (images.length > 1)', start);
    final carousel = source.substring(start, end);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    expect(carousel, contains('PageView.builder'));
    expect(carousel, contains('onPageChanged'));
    expect(carousel, contains('MerchantPhotoContent'));
    expect(carousel, isNot(contains('InkWell')));
    expect(carousel, isNot(contains('Navigator.of(context)')));
    expect(carousel, isNot(contains('InteractiveViewer')));
  });
}
