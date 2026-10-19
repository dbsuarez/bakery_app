import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

class CustomerPortalLinkStatus {
  final bool exists;
  final bool enabled;
  final String? token;
  final DateTime? createdAt;
  final DateTime? lastAccessedAt;

  const CustomerPortalLinkStatus({
    required this.exists,
    required this.enabled,
    this.token,
    this.createdAt,
    this.lastAccessedAt,
  });

  factory CustomerPortalLinkStatus.fromJson(Map<String, dynamic> json) {
    return CustomerPortalLinkStatus(
      exists: json['exists'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? false,
      token: json['token'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      lastAccessedAt: DateTime.tryParse(
        json['last_accessed_at'] as String? ?? '',
      ),
    );
  }
}

class CustomerPortalService {
  final SupabaseClient client;

  const CustomerPortalService(this.client);

  Future<CustomerPortalLinkStatus> status(String customerRemoteId) async {
    final value = await client.rpc(
      'customer_soa_link_status',
      params: {'p_customer_id': customerRemoteId},
    );
    return CustomerPortalLinkStatus.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
  }

  /// Creates a new link or invalidates and replaces the previous link.
  /// The returned secret cannot be recovered later because only its hash is
  /// stored in the database.
  Future<String> rotateLink(String customerRemoteId) async {
    final token =
        await client.rpc(
              'rotate_customer_soa_link',
              params: {'p_customer_id': customerRemoteId},
            )
            as String;
    return linkForToken(token);
  }

  Future<void> revokeLink(String customerRemoteId) async {
    await client.rpc(
      'revoke_customer_soa_link',
      params: {'p_customer_id': customerRemoteId},
    );
  }

  Future<Map<String, dynamic>> loadStatement(String token) async {
    final value = await client.rpc(
      'get_customer_soa',
      params: {'p_token': token},
    );
    return Map<String, dynamic>.from(value as Map);
  }

  String linkForToken(String token) => _portalUri(token).toString();

  Uri _portalUri(String token) {
    final configured = SupabaseConfig.customerPortalUrl.trim();
    if (configured.isNotEmpty) {
      return Uri.parse(configured)
          .resolve('soa.html')
          .replace(queryParameters: {'soa': token});
    }
    if (kIsWeb) {
      return Uri.base
          .resolve('/soa.html')
          .replace(queryParameters: {'soa': token}, fragment: '');
    }
    throw StateError(
      'CUSTOMER_PORTAL_URL is required when creating links outside the web app.',
    );
  }
}
