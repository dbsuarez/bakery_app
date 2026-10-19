import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('Usage: dart run tool/sanitize_backup.dart INPUT OUTPUT');
    exitCode = 64;
    return;
  }
  final input = File(args[0]);
  final output = File(args[1]);
  if (output.existsSync()) {
    stderr.writeln('Refusing to overwrite ${output.path}');
    exitCode = 73;
    return;
  }

  final backup = Map<String, dynamic>.from(
    jsonDecode(input.readAsStringSync()) as Map,
  );
  Set<int> ids(String key) => (backup[key] as List)
      .map((row) => (row as Map)['id'] as int)
      .toSet();
  final products = ids('products');
  final customers = ids('customers');
  final batches = ids('batches');
  final sales = ids('sales');

  List<dynamic> retain(String key, bool Function(Map<dynamic, dynamic>) keep) {
    final rows = backup[key] as List;
    final result = rows.where((row) => keep(row as Map)).toList();
    stdout.writeln('$key: ${rows.length} -> ${result.length}');
    return result;
  }

  backup['sale_payments'] = retain(
    'sale_payments',
    (row) => sales.contains(row['sale_id']),
  );
  backup['customer_credits'] = retain(
    'customer_credits',
    (row) =>
        customers.contains(row['customer_id']) &&
        (row['sale_id'] == null || sales.contains(row['sale_id'])),
  );
  backup['loyalty_adjustments'] = retain(
    'loyalty_adjustments',
    (row) => customers.contains(row['customer_id']),
  );
  backup['customer_favorites'] = retain(
    'customer_favorites',
    (row) =>
        customers.contains(row['customer_id']) &&
        products.contains(row['product_id']),
  );
  backup['favorite_dismissals'] = retain(
    'favorite_dismissals',
    (row) =>
        customers.contains(row['customer_id']) &&
        batches.contains(row['batch_id']),
  );

  output.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(backup));
  stdout.writeln('Wrote ${output.path}');
}
