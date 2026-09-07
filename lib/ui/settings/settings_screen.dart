import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_state.dart';
import '../../backup/backup_service.dart' as backup;
import '../../build_info.dart';
import '../../repository/bakery_repository.dart';
import '../../repository/remote_repository.dart';
import '../../reports/csv_report_service.dart' as reports;
import '../../security/app_lock_service.dart';
import '../../settings/business_settings_controller.dart';
import '../../theme/theme_controller.dart';
import '../../utils/app_date_format.dart';
import '../import/import_screen.dart';
import '../import/restore_screen.dart';
import '../products/products_list_screen.dart';
import 'qr_codes_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _exporting = false;
  bool _exportingReport = false;
  Future<_LockState>? _lockStateFuture;

  @override
  void initState() {
    super.initState();
    // The business name lives on the account, not this device - refresh it
    // whenever Settings opens in case another device changed it.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<BusinessSettingsController>().load(),
    );
  }

  void _reloadLockState(AppLockService lockService) {
    setState(() => _lockStateFuture = _loadLockState(lockService));
  }

  Future<_LockState> _loadLockState(AppLockService lockService) async {
    final auth = LocalAuthentication();
    final enabled = await lockService.isEnabled();
    final biometricEnabled =
        enabled ? await lockService.isBiometricEnabled() : false;
    bool biometricAvailable = false;
    try {
      biometricAvailable = await auth.isDeviceSupported();
    } catch (_) {
      biometricAvailable = false;
    }
    return _LockState(
      enabled: enabled,
      biometricEnabled: biometricEnabled,
      biometricAvailable: biometricAvailable,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lockService = context.watch<AppLockService?>();
    _lockStateFuture ??=
        lockService == null ? null : _loadLockState(lockService);
    final email = Supabase.instance.client.auth.currentUser?.email;
    final repo = context.read<BakeryRepository>() as RemoteRepository;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Account'),
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: const Text('Signed in as'),
            subtitle: Text(email ?? '-'),
          ),
          const _SectionHeader('Business'),
          Consumer<BusinessSettingsController>(
            builder: (context, business, _) => ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Business name'),
              subtitle: Text(business.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editBusinessName(context, business),
            ),
          ),
          Consumer<BusinessSettingsController>(
            builder: (context, business, _) => ListTile(
              leading: const Icon(Icons.redeem_outlined),
              title: const Text('Loyalty points'),
              subtitle: Text(
                'Earn: ₱${business.pesosPerPoint.toStringAsFixed(0)} = 1 point '
                '(+${business.sameDayBonusPercent.toStringAsFixed(0)}% same-day) · '
                'Redeem: 1 pt = ₱${business.redeemPesosPerPoint.toStringAsFixed(0)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editPointsSettings(context, business),
            ),
          ),
          Consumer<BusinessSettingsController>(
            builder: (context, business, _) => ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Customer groups'),
              subtitle: Text(
                business.customerGroups.isEmpty
                    ? 'None configured - e.g. Office, Central'
                    : business.customerGroups.join(', '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editCustomerGroups(context, business),
            ),
          ),
          Consumer<BusinessSettingsController>(
            builder: (context, business, _) => ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Payment methods'),
              subtitle: Text(business.paymentMethods.join(', ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editPaymentMethods(context, business),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_2),
            title: const Text('Payment QR codes'),
            subtitle: const Text('Up to 3 - shown on statement PDFs'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const QrCodesScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.bakery_dining_outlined),
            title: const Text('Products'),
            subtitle: const Text('Rename products'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProductsListScreen()),
            ),
          ),
          const _SectionHeader('Sync status'),
          ValueListenableBuilder<String?>(
            valueListenable: repo.lastFetchError,
            builder: (context, error, _) {
              if (error == null) return const SizedBox.shrink();
              return ListTile(
                leading: const Icon(Icons.cloud_off, color: Colors.red),
                title: const Text('Data connection issue'),
                subtitle: Text(error),
              );
            },
          ),
          ValueListenableBuilder<Map<String, String>>(
            valueListenable: repo.lastFetchInfo,
            builder: (context, info, _) {
              if (info.isEmpty) {
                return const ListTile(
                  leading: Icon(Icons.hourglass_empty),
                  title: Text('Data fetch: no successful poll yet'),
                  dense: true,
                );
              }
              return ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Last successful fetch per table'),
                subtitle: Text(
                  info.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
                ),
                dense: true,
              );
            },
          ),
          const _SectionHeader('Data'),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Import Latest Spreadsheet'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ImportScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore from Backup'),
            subtitle: const Text('Load data from an exported JSON backup'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RestoreScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Export Backup (JSON)'),
            subtitle: const Text('Save a copy of all products, customers, batches, and sales'),
            trailing: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _exporting ? null : () => _exportBackup(context),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Export Sales Report (CSV)'),
            subtitle: const Text('A spreadsheet-ready ledger for a date range'),
            trailing: _exportingReport
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _exportingReport ? null : () => _showReportRangeDialog(context),
          ),
          const _SectionHeader('Appearance'),
          Consumer<ThemeController>(
            builder: (context, themeController, _) => SwitchListTile(
              secondary: const Icon(Icons.short_text),
              title: const Text('Show card descriptions on Dashboard'),
              subtitle: const Text(
                'Turn off to shrink the Dashboard cards to just label and value',
              ),
              value: themeController.showCardDescriptions,
              onChanged: (v) => themeController.setShowCardDescriptions(v),
            ),
          ),
          const _ThemeSection(),
          if (lockService != null) ...[
            const _SectionHeader('Security'),
            FutureBuilder<_LockState>(
              future: _lockStateFuture,
              builder: (context, snapshot) {
                final state = snapshot.data;
                if (state == null) {
                  return const ListTile(
                    leading: Icon(Icons.lock_outline),
                    title: Text('App Lock'),
                    trailing: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.lock_outline),
                      title: const Text('Require PIN to open app'),
                      value: state.enabled,
                      onChanged: (value) => value
                          ? _enableLock(context, lockService)
                          : _disableLock(context, lockService),
                    ),
                    if (state.enabled) ...[
                      ListTile(
                        leading: const Icon(Icons.password),
                        title: const Text('Change PIN'),
                        onTap: () => _changePin(context, lockService),
                      ),
                      if (state.biometricAvailable)
                        SwitchListTile(
                          secondary: const Icon(Icons.fingerprint),
                          title: const Text('Use biometrics'),
                          value: state.biometricEnabled,
                          onChanged: (value) async {
                            await lockService.setBiometricEnabled(value);
                            _reloadLockState(lockService);
                          },
                        ),
                    ],
                  ],
                );
              },
            ),
          ],
          const _SectionHeader('Session'),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => Supabase.instance.client.auth.signOut(),
          ),
          const _SectionHeader('About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Build'),
            subtitle: Text(buildTime),
            dense: true,
          ),
        ],
      ),
    );
  }

  Future<void> _enableLock(
    BuildContext context,
    AppLockService lockService,
  ) async {
    final pin = await _promptNewPin(context);
    if (pin == null) return;
    await lockService.setPin(pin);
    if (!mounted) return;
    _reloadLockState(lockService);
  }

  Future<void> _disableLock(
    BuildContext context,
    AppLockService lockService,
  ) async {
    final pin = await _promptPin(context, title: 'Enter current PIN to turn off');
    if (pin == null) return;
    final ok = await lockService.verifyPin(pin);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Incorrect PIN')));
      return;
    }
    await lockService.disable();
    if (!mounted) return;
    _reloadLockState(lockService);
  }

  Future<void> _changePin(
    BuildContext context,
    AppLockService lockService,
  ) async {
    final currentPin = await _promptPin(context, title: 'Enter current PIN');
    if (currentPin == null) return;
    final ok = await lockService.verifyPin(currentPin);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Incorrect PIN')));
      return;
    }
    final newPin = await _promptNewPin(context);
    if (newPin == null) return;
    await lockService.setPin(newPin);
    if (!context.mounted) return;
    _reloadLockState(lockService);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('PIN updated')));
  }

  Future<String?> _promptPin(
    BuildContext context, {
    required String title,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(counterText: ''),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (result == null || result.length < 4) return null;
    return result;
  }

  Future<String?> _promptNewPin(BuildContext context) async {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    String? error;
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Set a PIN'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pinController,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: '4-6 digit PIN',
                    counterText: '',
                  ),
                ),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Confirm PIN',
                    counterText: '',
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final pin = pinController.text;
                  if (pin.length < 4) {
                    setDialogState(() => error = 'PIN must be at least 4 digits');
                    return;
                  }
                  if (pin != confirmController.text) {
                    setDialogState(() => error = 'PINs do not match');
                    return;
                  }
                  Navigator.of(context).pop(pin);
                },
                child: const Text('Set PIN'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editBusinessName(
    BuildContext context,
    BusinessSettingsController business,
  ) async {
    final controller = TextEditingController(text: business.name);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Business name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != true) return;
    await business.setName(controller.text);
  }

  Future<void> _editPointsSettings(
    BuildContext context,
    BusinessSettingsController business,
  ) async {
    final rateController =
        TextEditingController(text: business.pesosPerPoint.toStringAsFixed(0));
    final bonusController = TextEditingController(
        text: business.sameDayBonusPercent.toStringAsFixed(0));
    final redeemRateController = TextEditingController(
        text: business.redeemPesosPerPoint.toStringAsFixed(0));
    var bonusStartDate = business.sameDayBonusStartDate;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Loyalty points'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: rateController,
                  decoration: const InputDecoration(
                    labelText: 'Pesos per point (earning)',
                    helperText: 'e.g. 10 means ₱10 spent = 1 point earned',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                TextField(
                  controller: bonusController,
                  decoration: const InputDecoration(
                    labelText: 'Same-day payment bonus (%)',
                    helperText: 'Extra points when paid the same day as the sale',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Same-day bonus starts from'),
                  subtitle: Text(
                    '${appDateFormat.format(bonusStartDate)}\n'
                    'Sales before this date never get the same-day bonus, '
                    'even if marked paid the same day - useful when early '
                    'payment dates weren\'t tracked precisely.',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: bonusStartDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setDialogState(() => bonusStartDate = picked);
                    }
                  },
                ),
                TextField(
                  controller: redeemRateController,
                  decoration: const InputDecoration(
                    labelText: 'Peso value per point (redeeming)',
                    helperText: 'e.g. 1 means 1 point covers ₱1 of a product',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result != true) return;
    final rate = double.tryParse(rateController.text);
    final bonus = double.tryParse(bonusController.text);
    final redeemRate = double.tryParse(redeemRateController.text);
    if (rate != null && rate > 0) await business.setPesosPerPoint(rate);
    if (bonus != null && bonus >= 0) {
      await business.setSameDayBonusPercent(bonus);
    }
    if (redeemRate != null && redeemRate > 0) {
      await business.setRedeemPesosPerPoint(redeemRate);
    }
    if (bonusStartDate != business.sameDayBonusStartDate) {
      await business.setSameDayBonusStartDate(bonusStartDate);
    }
  }

  Future<void> _editCustomerGroups(
    BuildContext context,
    BusinessSettingsController business,
  ) async {
    var groups = List<String>.from(business.customerGroups);
    final newGroupController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void addGroup() {
            final value = newGroupController.text.trim();
            if (value.isEmpty || groups.contains(value)) return;
            setDialogState(() {
              groups = [...groups, value];
              newGroupController.clear();
            });
          }

          return AlertDialog(
            title: const Text('Customer groups'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tag customers by office, location, or any grouping you '
                    'want - e.g. "Office", "Central".',
                  ),
                  const SizedBox(height: 12),
                  if (groups.isEmpty)
                    const Text('No groups yet.')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final g in groups)
                          Chip(
                            label: Text(g),
                            onDeleted: () => setDialogState(
                                () => groups = groups.where((x) => x != g).toList()),
                          ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: newGroupController,
                          decoration:
                              const InputDecoration(labelText: 'New group name'),
                          onSubmitted: (_) => addGroup(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: addGroup,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    if (result != true) return;
    await business.setCustomerGroups(groups);
  }

  Future<void> _editPaymentMethods(
    BuildContext context,
    BusinessSettingsController business,
  ) async {
    var methods = List<String>.from(business.paymentMethods);
    final newMethodController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void addMethod() {
            final value = newMethodController.text.trim();
            if (value.isEmpty || methods.contains(value)) return;
            setDialogState(() {
              methods = [...methods, value];
              newMethodController.clear();
            });
          }

          return AlertDialog(
            title: const Text('Payment methods'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Shown as choices whenever a payment is recorded.',
                  ),
                  const SizedBox(height: 12),
                  if (methods.isEmpty)
                    const Text('No methods yet.')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in methods)
                          Chip(
                            label: Text(m),
                            onDeleted: () => setDialogState(
                                () => methods = methods.where((x) => x != m).toList()),
                          ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: newMethodController,
                          decoration:
                              const InputDecoration(labelText: 'New method name'),
                          onSubmitted: (_) => addMethod(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: addMethod,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    if (result != true) return;
    await business.setPaymentMethods(methods);
  }

  Future<void> _exportBackup(BuildContext context) async {
    setState(() => _exporting = true);
    try {
      await backup.exportBackup(context.read<AppState>());
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _showReportRangeDialog(BuildContext context) async {
    final now = DateTime.now();
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Export sales report'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('this_month'),
            child: const Text('This month'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('last_month'),
            child: const Text('Last month'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('all_time'),
            child: const Text('All time'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('custom'),
            child: const Text('Custom range...'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;

    DateTime? start;
    DateTime? end;
    String rangeLabel;
    switch (choice) {
      case 'this_month':
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 1)
            .subtract(const Duration(milliseconds: 1));
        rangeLabel = DateFormat('yyyy-MM').format(now);
        break;
      case 'last_month':
        final lastMonth = DateTime(now.year, now.month - 1, 1);
        start = lastMonth;
        end = DateTime(now.year, now.month, 1)
            .subtract(const Duration(milliseconds: 1));
        rangeLabel = DateFormat('yyyy-MM').format(lastMonth);
        break;
      case 'all_time':
        start = null;
        end = null;
        rangeLabel = 'all_time';
        break;
      case 'custom':
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
          initialDateRange: DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: now,
          ),
        );
        if (range == null || !context.mounted) return;
        start = range.start;
        end = range.end.add(const Duration(
            hours: 23, minutes: 59, seconds: 59));
        rangeLabel =
            '${appDateFormat.format(range.start)}_to_${appDateFormat.format(range.end)}';
        break;
      default:
        return;
    }

    setState(() => _exportingReport = true);
    try {
      await reports.exportSalesCsv(
        context.read<AppState>(),
        start: start,
        end: end,
        rangeLabel: rangeLabel,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exportingReport = false);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

class _ThemeSection extends StatelessWidget {
  const _ThemeSection();

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Theme'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode),
                label: Text('Dark'),
              ),
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto),
                label: Text('System'),
              ),
            ],
            selected: {themeController.mode},
            onSelectionChanged: (s) => themeController.setMode(s.first),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final preset in themePresets)
                _ThemeSwatch(
                  preset: preset,
                  selected: preset.id == themeController.preset.id,
                  onTap: () => themeController.setPreset(preset),
                ),
              _CustomThemeSwatch(
                selected: themeController.isCustom,
                color: themeController.isCustom
                    ? themeController.customColor
                    : null,
                onTap: () => _pickCustomColor(context, themeController),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Future<void> _pickCustomColor(
    BuildContext context,
    ThemeController themeController,
  ) async {
    final result = await showDialog<Color>(
      context: context,
      builder: (context) => _CustomColorDialog(
        initial: themeController.isCustom
            ? themeController.customColor
            : themePresets.first.seedColor,
      ),
    );
    if (result != null) {
      await themeController.setCustomColor(result);
    }
  }
}

class _ThemeSwatch extends StatelessWidget {
  final ThemePreset preset;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeSwatch({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Tooltip(
        message: preset.label,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: preset.seedColor,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(
                    color: Theme.of(context).colorScheme.onSurface,
                    width: 3,
                  )
                : null,
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 20)
              : null,
        ),
      ),
    );
  }
}

class _CustomThemeSwatch extends StatelessWidget {
  final bool selected;
  final Color? color;
  final VoidCallback onTap;
  const _CustomThemeSwatch({
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Tooltip(
        message: 'Custom color',
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            gradient: color == null
                ? const SweepGradient(colors: [
                    Colors.red,
                    Colors.yellow,
                    Colors.green,
                    Colors.cyan,
                    Colors.blue,
                    Colors.purple,
                    Colors.red,
                  ])
                : null,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(
                    color: Theme.of(context).colorScheme.onSurface,
                    width: 3,
                  )
                : null,
          ),
          child: Icon(
            selected ? Icons.check : Icons.edit,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _CustomColorDialog extends StatefulWidget {
  final Color initial;
  const _CustomColorDialog({required this.initial});

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late double _r;
  late double _g;
  late double _b;
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _r = widget.initial.r * 255;
    _g = widget.initial.g * 255;
    _b = widget.initial.b * 255;
    _hexController = TextEditingController(text: _hex);
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color get _color =>
      Color.fromARGB(255, _r.round(), _g.round(), _b.round());

  String get _hex =>
      '#${_r.round().toRadixString(16).padLeft(2, '0')}'
      '${_g.round().toRadixString(16).padLeft(2, '0')}'
      '${_b.round().toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();

  void _applyHex(String value) {
    final cleaned = value.replaceAll('#', '').trim();
    if (cleaned.length != 6) return;
    final parsed = int.tryParse(cleaned, radix: 16);
    if (parsed == null) return;
    setState(() {
      _r = ((parsed >> 16) & 0xFF).toDouble();
      _g = ((parsed >> 8) & 0xFF).toDouble();
      _b = (parsed & 0xFF).toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pick a custom color'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            height: 56,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: _color,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          _ColorSlider(
            label: 'R',
            value: _r,
            color: Colors.red,
            onChanged: (v) {
              setState(() => _r = v);
              _hexController.text = _hex;
            },
          ),
          _ColorSlider(
            label: 'G',
            value: _g,
            color: Colors.green,
            onChanged: (v) {
              setState(() => _g = v);
              _hexController.text = _hex;
            },
          ),
          _ColorSlider(
            label: 'B',
            value: _b,
            color: Colors.blue,
            onChanged: (v) {
              setState(() => _b = v);
              _hexController.text = _hex;
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _hexController,
            decoration: const InputDecoration(labelText: 'Hex'),
            textCapitalization: TextCapitalization.characters,
            onSubmitted: _applyHex,
            onChanged: _applyHex,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_color),
          child: const Text('Use this color'),
        ),
      ],
    );
  }
}

class _ColorSlider extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;
  const _ColorSlider({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 16, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            activeColor: color,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 32, child: Text('${value.round()}')),
      ],
    );
  }
}

class _LockState {
  final bool enabled;
  final bool biometricEnabled;
  final bool biometricAvailable;

  const _LockState({
    required this.enabled,
    required this.biometricEnabled,
    required this.biometricAvailable,
  });
}
