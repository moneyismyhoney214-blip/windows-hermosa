import 'api_constants.dart';
import 'base_client.dart';

class NearPaySessionService {
  NearPaySessionService({BaseClient? client})
      : _client = client ?? BaseClient();

  final BaseClient _client;
  String? _lastSessionId;
  String? _lastTransactionId;

  String? get lastSessionId => _lastSessionId;
  String? get lastTransactionId => _lastTransactionId;

  Map<String, dynamic> _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  String? _asNonEmpty(dynamic value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty || raw == 'null') return null;
    return raw;
  }

  String? extractSessionId(Map<String, dynamic> payload) {
    final direct = _asNonEmpty(
      payload['session_id'] ??
          payload['sessionId'] ??
          payload['id'] ??
          payload['uuid'],
    );
    if (direct != null) return direct;
    final data = _asStringMap(payload['data']);
    return _asNonEmpty(
      data['session_id'] ?? data['sessionId'] ?? data['id'] ?? data['uuid'],
    );
  }

  String? extractTransactionId(Map<String, dynamic> payload) {
    final direct = _asNonEmpty(
      payload['transaction_id'] ??
          payload['transactionId'] ??
          payload['original_transaction'],
    );
    if (direct != null) return direct;
    final data = _asStringMap(payload['data']);
    return _asNonEmpty(
      data['transaction_id'] ??
          data['transactionId'] ??
          data['original_transaction'],
    );
  }

  String? extractStatus(Map<String, dynamic> payload) {
    final direct = _asNonEmpty(
      payload['status'] ?? payload['state'] ?? payload['session_status'],
    );
    if (direct != null) return direct.toLowerCase();
    final data = _asStringMap(payload['data']);
    return _asNonEmpty(
      data['status'] ?? data['state'] ?? data['session_status'],
    )?.toLowerCase();
  }

  Future<Map<String, dynamic>> createPurchaseSession({
    required int branchId,
    required double amount,
    required String referenceId,
  }) async {
    final response =
        await _client.post(ApiConstants.nearPayPurchaseSessionEndpoint, {
      'branch_id': branchId,
      'amount': amount,
      'reference_id': referenceId,
    });
    final payload = _asStringMap(response);
    _lastSessionId = extractSessionId(payload) ?? _lastSessionId;
    return payload;
  }

  Future<Map<String, dynamic>> createRefundSession({
    required int branchId,
    required double amount,
    required String originalTransaction,
    required String referenceId,
  }) async {
    final response =
        await _client.post(ApiConstants.nearPayRefundSessionEndpoint, {
      'branch_id': branchId,
      'amount': amount,
      'original_transaction': originalTransaction,
      'reference_id': referenceId,
    });
    final payload = _asStringMap(response);
    _lastSessionId = extractSessionId(payload) ?? _lastSessionId;
    return payload;
  }

  Future<Map<String, dynamic>> getSessionStatus([String? sessionId]) async {
    final effectiveSessionId = _asNonEmpty(sessionId) ?? _lastSessionId;
    if (effectiveSessionId == null) {
      throw Exception('Session ID is required');
    }
    final response = await _client.get(
      ApiConstants.nearPaySessionStatusEndpoint(effectiveSessionId),
    );
    final payload = _asStringMap(response);
    _lastSessionId = extractSessionId(payload) ?? _lastSessionId;
    _lastTransactionId = extractTransactionId(payload) ?? _lastTransactionId;
    return payload;
  }

  bool isTerminalState(String? status) {
    final s = (status ?? '').toLowerCase().trim();
    if (s.isEmpty) return false;
    const terminal = {
      'success',
      'completed',
      'paid',
      'failed',
      'error',
      'cancelled',
      'canceled',
      'refunded',
      'declined',
    };
    return terminal.contains(s);
  }

  List<Map<String, dynamic>> extractTransactions(dynamic response) {
    final payload = _asStringMap(response);
    final data = payload['data'];
    final dataMap = _asStringMap(data);
    final transactions = dataMap['transactions'];
    final source = transactions is List
        ? transactions
        : data is List
            ? data
            : response is List
                ? response
                : const [];
    return source
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList(growable: false);
  }

  bool isNearPayNotConfiguredError(dynamic error) {
    final text = error?.toString().toLowerCase() ?? '';
    return text.contains('nearpay is not configured') ||
        text.contains('nearpay_api_key');
  }

  Future<Map<String, dynamic>> getAllTransactions() async {
    final response =
        await _client.get(ApiConstants.nearPayTransactionsEndpoint);
    return _asStringMap(response);
  }

  Future<Map<String, dynamic>> getTransactionById(String transactionId) async {
    final normalized = transactionId.trim();
    if (normalized.isEmpty) {
      throw ApiException('NearPay transaction id is required');
    }
    final response = await _client.get(
      ApiConstants.nearPayTransactionByIdEndpoint(normalized),
    );
    return _asStringMap(response);
  }

  Future<Map<String, dynamic>> pollUntilTerminal({
    String? sessionId,
    Duration timeout = const Duration(seconds: 120),
    Duration interval = const Duration(seconds: 2),
    void Function(Map<String, dynamic> snapshot)? onTick,
  }) async {
    final deadline = DateTime.now().add(timeout);
    Map<String, dynamic> latest = const {};
    while (DateTime.now().isBefore(deadline)) {
      latest = await getSessionStatus(sessionId);
      onTick?.call(latest);
      final status = extractStatus(latest);
      if (isTerminalState(status)) {
        return latest;
      }
      await Future.delayed(interval);
    }
    return latest;
  }
}
