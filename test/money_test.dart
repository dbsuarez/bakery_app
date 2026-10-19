import 'package:bakery_app/utils/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aggregates decimal money using integer centavos', () {
    expect(sumMoney([0.1, 0.2]), 0.30);
    expect(toCentavos(19.999), 2000);
    expect(subtractMoney(100, 33.33), 66.67);
  });
}
