import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../repository/bakery_repository.dart';
import '../../repository/remote_repository.dart';

class SyncStatusStrip extends StatelessWidget {
  const SyncStatusStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<BakeryRepository>() as RemoteRepository;
    return ValueListenableBuilder<bool>(
      valueListenable: repo.isFetching,
      builder: (context, fetching, _) => ValueListenableBuilder<String?>(
        valueListenable: repo.lastFetchError,
        builder: (context, error, _) =>
            ValueListenableBuilder<Map<String, String>>(
              valueListenable: repo.lastFetchInfo,
              builder: (context, info, _) {
                final failed = error != null;
                final colors = Theme.of(context).colorScheme;
                final color = failed
                    ? colors.errorContainer
                    : fetching
                    ? colors.tertiaryContainer
                    : colors.secondaryContainer;
                final icon = failed
                    ? Icons.cloud_off_outlined
                    : fetching
                    ? Icons.sync
                    : Icons.cloud_done_outlined;
                final text = failed
                    ? 'Sync failed - tap to retry'
                    : fetching
                    ? 'Syncing...'
                    : info.isEmpty
                    ? 'Connecting...'
                    : 'Synced';
                return Material(
                  color: color,
                  child: InkWell(
                    onTap: fetching ? null : repo.refresh,
                    child: SizedBox(
                      height: 30,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 15),
                          const SizedBox(width: 6),
                          Text(
                            text,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
      ),
    );
  }
}
