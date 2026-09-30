import 'package:flutter_test/flutter_test.dart';
import 'package:proxi_play/utils/merchant_prize_claim_flow.dart';

void main() {
  test('a successful transaction enables the confirmation state', () {
    final flow = MerchantPrizeClaimFlow();
    expect(flow.start(), isTrue);
    expect(flow.isSubmitting, isTrue);

    flow.succeed();

    expect(flow.isSubmitting, isFalse);
    expect(flow.isClaimed, isTrue);
  });

  test('a failed transaction never enables the confirmation state', () {
    final flow = MerchantPrizeClaimFlow();
    expect(flow.start(), isTrue);

    flow.fail();

    expect(flow.isSubmitting, isFalse);
    expect(flow.isClaimed, isFalse);
  });

  test('two quick taps only start one transaction', () {
    final flow = MerchantPrizeClaimFlow();
    expect(flow.start(), isTrue);
    expect(flow.start(), isFalse);
  });

  test('an already claimed lot cannot start another transaction', () {
    final flow = MerchantPrizeClaimFlow();
    flow.start();
    flow.succeed();

    expect(flow.start(), isFalse);
  });
}
