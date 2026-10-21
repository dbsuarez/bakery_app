import 'package:bakery_app/repository/remote_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('remittance mutation guard', () {
    test('rejects a locked batch', () {
      expect(
        () => ensureBatchTransactionsMutable(locked: true),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Unlock the batch first'),
          ),
        ),
      );
    });

    test('allows a remitted batch after its lock was cleared', () {
      expect(
        () => ensureBatchTransactionsMutable(locked: false),
        returnsNormally,
      );
    });
  });
}
