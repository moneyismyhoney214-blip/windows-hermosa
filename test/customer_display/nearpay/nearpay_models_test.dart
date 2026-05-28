import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/customer_display/nearpay/nearpay_backend_service.dart';

/// Tests for the model `fromJson` constructors in
/// `nearpay_backend_service.dart`. The audit flagged the entire NearPay
/// module as untested; the backend service has its own coverage, but
/// the model parsing is where most edge-case bugs hide (the NearPay
/// API returns slightly different shapes across SDK versions).
void main() {
  group('NearPayPurchaseSession.fromJson', () {
    test('parses the canonical shape', () {
      final s = NearPayPurchaseSession.fromJson(const {
        'session_id': 's-1',
        'terminal_id': 't-1',
        'amount': 5000,
        'reference_id': 'INV-1',
        'status': 'new',
        'type': 'purchase',
        'expired_at': 1747000000,
        'client_id': 'c-1',
      });
      expect(s.sessionId, 's-1');
      expect(s.terminalId, 't-1');
      expect(s.amount, 5000);
      expect(s.referenceId, 'INV-1');
      expect(s.status, 'new');
      expect(s.type, 'purchase');
      expect(s.expiresAt, 1747000000);
      expect(s.clientId, 'c-1');
    });

    test('accepts amount as a string and coerces to int', () {
      final s = NearPayPurchaseSession.fromJson(const {
        'session_id': 's',
        'terminal_id': 't',
        'amount': '1234',
        'reference_id': 'r',
        'status': 'new',
        'type': 'purchase',
      });
      expect(s.amount, 1234);
    });

    test('falls back to nested terminal.id when terminal_id is missing', () {
      final s = NearPayPurchaseSession.fromJson(const {
        'session_id': 's',
        'terminal': {'id': 'nested-t-1'},
        'amount': 1,
        'reference_id': 'r',
        'status': 'new',
        'type': 'purchase',
      });
      expect(s.terminalId, 'nested-t-1');
    });

    test('expires_at and expired_at are both accepted', () {
      final a = NearPayPurchaseSession.fromJson(const {
        'session_id': 's',
        'terminal_id': 't',
        'amount': 1,
        'reference_id': 'r',
        'status': 'new',
        'type': 'purchase',
        'expires_at': 99,
      });
      final b = NearPayPurchaseSession.fromJson(const {
        'session_id': 's',
        'terminal_id': 't',
        'amount': 1,
        'reference_id': 'r',
        'status': 'new',
        'type': 'purchase',
        'expired_at': 88,
      });
      expect(a.expiresAt, 99);
      expect(b.expiresAt, 88);
    });

    test('missing required fields throws FormatException', () {
      expect(
        () => NearPayPurchaseSession.fromJson(const {
          'terminal_id': 't',
          'amount': 1,
          'reference_id': 'r',
          'status': 'new',
          'type': 'purchase',
          // session_id missing
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('NearPaySessionStatus.fromJson + status helpers', () {
    Map<String, dynamic> baseStatus({
      String status = 'new',
      String type = 'purchase',
    }) =>
        {
          'session_id': 's-1',
          'status': status,
          'type': type,
          'amount': 100,
          'reference_id': 'INV-1',
        };

    test('completed flag', () {
      final s = NearPaySessionStatus.fromJson(baseStatus(status: 'completed'));
      expect(s.isCompleted, isTrue);
      expect(s.isFailed, isFalse);
      expect(s.isPending, isFalse);
      expect(s.isExpired, isFalse);
    });

    test('failed flag', () {
      final s = NearPaySessionStatus.fromJson(baseStatus(status: 'failed'));
      expect(s.isFailed, isTrue);
      expect(s.isCompleted, isFalse);
    });

    test('expired flag', () {
      final s = NearPaySessionStatus.fromJson(baseStatus(status: 'expired'));
      expect(s.isExpired, isTrue);
      expect(s.isPending, isFalse);
    });

    test('"new" and "processing" both count as pending', () {
      expect(
        NearPaySessionStatus.fromJson(baseStatus(status: 'new')).isPending,
        isTrue,
      );
      expect(
        NearPaySessionStatus.fromJson(baseStatus(status: 'processing'))
            .isPending,
        isTrue,
      );
    });

    test('parses ISO8601 timestamps when present', () {
      final s = NearPaySessionStatus.fromJson({
        ...baseStatus(),
        'created_at': '2026-05-19T10:00:00Z',
        'updated_at': '2026-05-19T10:01:00Z',
        'expires_at': '2026-05-19T11:00:00Z',
        'transaction_id': 'tx-1',
      });
      expect(s.transactionId, 'tx-1');
      expect(s.createdAt!.toUtc().hour, 10);
      expect(s.updatedAt!.toUtc().minute, 1);
      expect(s.expiresAt!.toUtc().hour, 11);
    });

    test('omitting optional timestamps leaves them null', () {
      final s = NearPaySessionStatus.fromJson(baseStatus());
      expect(s.transactionId, isNull);
      expect(s.createdAt, isNull);
      expect(s.updatedAt, isNull);
      expect(s.expiresAt, isNull);
    });
  });

  group('NearPayTerminalDetails.fromJson', () {
    test('reads merchant + identity fields', () {
      final t = NearPayTerminalDetails.fromJson(const {
        'id': 'term-uuid',
        'tid': 'TID12345',
        'name': 'Front Counter',
        'name_ar': 'الكاشير الأمامي',
        'is_assigned': true,
        'user_uuid': 'usr-1',
        'merchant': {
          'id': 'm-1',
          'name': 'Hermosa Demo',
          'name_ar': 'هيرموسا',
        },
      });
      expect(t.terminalUuid, 'term-uuid');
      expect(t.tid, 'TID12345');
      expect(t.name, 'Front Counter');
      expect(t.nameAr, 'الكاشير الأمامي');
      expect(t.isAssignedToUser, isTrue);
      expect(t.userUuid, 'usr-1');
      expect(t.merchantId, 'm-1');
      expect(t.merchantName, 'Hermosa Demo');
      expect(t.merchantNameAr, 'هيرموسا');
    });

    test('userUuid falls back to client_uuid / merchant_uuid', () {
      final t = NearPayTerminalDetails.fromJson(const {
        'id': 't',
        'tid': 'tid',
        'client_uuid': 'cli-9',
      });
      expect(t.userUuid, 'cli-9');
    });

    test('is_assigned defaults to false when missing', () {
      final t = NearPayTerminalDetails.fromJson(const {
        'id': 't',
        'tid': 'tid',
      });
      expect(t.isAssignedToUser, isFalse);
    });
  });

  group('NearPayReconcileResult.fromJson', () {
    test('parses end-of-day settlement payload', () {
      final r = NearPayReconcileResult.fromJson(const {
        'reconcile_id': 'rec-1',
        'branch_id': 'b-7',
        'terminal_id': 't-1',
        'total_transactions': 12,
        'total_amount': 500000,
        'success_count': 11,
        'failed_count': 1,
        'status': 'completed',
        'created_at': '2026-05-19T22:00:00Z',
      });
      expect(r.reconcileId, 'rec-1');
      expect(r.branchId, 'b-7');
      expect(r.totalTransactions, 12);
      expect(r.totalAmount, 500000);
      expect(r.successCount, 11);
      expect(r.failedCount, 1);
      expect(r.status, 'completed');
      expect(r.createdAt!.toUtc().year, 2026);
    });

    test('createdAt is null when timestamp omitted', () {
      final r = NearPayReconcileResult.fromJson(const {
        'reconcile_id': 'r',
        'branch_id': 'b',
        'terminal_id': 't',
        'total_transactions': 0,
        'total_amount': 0,
        'success_count': 0,
        'failed_count': 0,
        'status': 'pending',
      });
      expect(r.createdAt, isNull);
    });
  });
}
