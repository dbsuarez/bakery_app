import 'package:bakery_app/repository/remote_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('remittance mutation guard', () {
    test('rejects a locked batch', () {
      expect(
        () => ensureBatchTransactionsMutable(locked: true, remitted: false),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Reopen the remittance first'),
          ),
        ),
      );
    });

    test('rejects a remitted batch even when its lock was cleared', () {
      expect(
        () => ensureBatchTransactionsMutable(locked: false, remitted: true),
        throwsA(isA<StateError>()),
      );
    });

    test('allows changes only after the remittance is reopened', () {
      expect(
        () => ensureBatchTransactionsMutable(locked: false, remitted: false),
        returnsNormally,
      );
    });
  });
}
