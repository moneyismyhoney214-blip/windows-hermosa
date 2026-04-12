import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hermosa_pos/locator.dart';
import 'package:hermosa_pos/models.dart';
import 'package:hermosa_pos/services/cache_service.dart';
import 'package:hermosa_pos/services/api/product_service.dart';

class DisabledMealState {
  final String mealId;
  final String mealName;
  final String? categoryName;
  final String? orderId;
  final String reason;
  final bool isDisabled;
  final DateTime updatedAt;
  final String source;

  const DisabledMealState({
    required this.mealId,
    required this.mealName,
    required this.reason,
    required this.isDisabled,
    required this.updatedAt,
    required this.source,
    this.categoryName,
    this.orderId,
  });

  Map<String, dynamic> toJson() => {
        'meal_id': mealId,
        'meal_name': mealName,
        'category_name': categoryName,
        'order_id': orderId,
        'reason': reason,
        'is_disabled': isDisabled,
        'updated_at': updatedAt.toIso8601String(),
        'source': source,
      };

  factory DisabledMealState.fromJson(Map<String, dynamic> json) {
    return DisabledMealState(
      mealId: json['meal_id']?.toString() ?? '',
      mealName: json['meal_name']?.toString() ?? 'Meal',
      categoryName: json['category_name']?.toString(),
      orderId: json['order_id']?.toString(),
      reason: json['reason']?.toString() ?? 'نفذت الوجبة',
      isDisabled: json['is_disabled'] == true,
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
      source: json['source']?.toString() ?? 'unknown',
    );
  }
}

class AvailabilityAuditEvent {
  final String action;
  final String mealId;
  final String details;
  final DateTime at;

  const AvailabilityAuditEvent({
    required this.action,
    required this.mealId,
    required this.details,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'action': action,
        'meal_id': mealId,
        'details': details,
        'at': at.toIso8601String(),
      };

  factory AvailabilityAuditEvent.fromJson(Map<String, dynamic> json) {
    return AvailabilityAuditEvent(
      action: json['action']?.toString() ?? 'unknown',
      mealId: json['meal_id']?.toString() ?? '',
      details: json['details']?.toString() ?? '',
      at: DateTime.tryParse(json['at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class KdsMealAvailabilityService extends ChangeNotifier {
  static const String _disabledMealsCacheKey = 'kds_disabled_meals';
  static const String _auditCacheKey = 'kds_disabled_meals_audit';
  static const Duration _refreshInterval = Duration(seconds: 5);
  static const Duration _circuitBreakDuration = Duration(seconds: 30);
  static const int _maxAuditSize = 150;

  final CacheService _cache = getIt<CacheService>();
  final ProductService _productService = getIt<ProductService>();

  final Map<String, DisabledMealState> _disabledMeals = {};
  final List<AvailabilityAuditEvent> _auditLog = [];

  Timer? _refreshTimer;
  bool _initialized = false;
  bool _refreshInProgress = false;

  int _failedRefreshCount = 0;
  DateTime? _circuitOpenedAt;

  Map<String, DisabledMealState> get disabledMeals =>
      Map<String, DisabledMealState>.unmodifiable(_disabledMeals);
  List<AvailabilityAuditEvent> get auditLog =>
      List<AvailabilityAuditEvent>.unmodifiable(_auditLog);

  bool get isCircuitOpen {
    if (_circuitOpenedAt == null) return false;
    final elapsed = DateTime.now().difference(_circuitOpenedAt!);
    if (elapsed > _circuitBreakDuration) {
      _circuitOpenedAt = null;
      return false;
    }
    return true;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _restoreCache();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      unawaited(refreshFromApi());
    });

    unawaited(refreshFromApi(force: true));
  }

  Future<void> disposeService() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _initialized = false;
  }

  Future<void> refreshFromApi({bool force = false}) async {
    if (_refreshInProgress) return;
    if (!force && isCircuitOpen) return;

    _refreshInProgress = true;
    try {
      final products = await _productService.getProducts(page: 1);
      final updated = <String, DisabledMealState>{};

      for (final product in products) {
        final existing = _disabledMeals[product.id];
        if (!product.isActive) {
          updated[product.id] = DisabledMealState(
            mealId: product.id,
            mealName: product.name,
            categoryName: product.category,
            orderId: existing?.orderId,
            reason: 'نفذت الوجبة',
            isDisabled: true,
            updatedAt: DateTime.now(),
            source: 'api',
          );
          continue;
        }

        // Keep recent KDS manual disable decisions for resiliency if API has no
        // dedicated stock status endpoint yet.
        if (existing != null &&
            existing.source == 'kds' &&
            existing.isDisabled &&
            DateTime.now().difference(existing.updatedAt) <
                const Duration(hours: 2)) {
          updated[product.id] = existing;
        }
      }

      _disabledMeals
        ..clear()
        ..addAll(updated);

      _failedRefreshCount = 0;
      _circuitOpenedAt = null;
      await _persistCache();
      notifyListeners();
    } catch (e) {
      _failedRefreshCount += 1;
      _appendAudit(
        action: 'refresh_failed',
        mealId: '-',
        details: 'refresh failed: $e',
      );
      if (_failedRefreshCount >= 3) {
        _circuitOpenedAt = DateTime.now();
      }
    } finally {
      _refreshInProgress = false;
    }
  }

  void applyKdsRealtimeUpdate(Map<String, dynamic> payload) {
    final mealId = payload['meal_id']?.toString().trim() ??
        payload['product_id']?.toString().trim() ??
        payload['productId']?.toString().trim() ??
        '';
    if (mealId.isEmpty) return;

    final isDisabled = payload['is_disabled'] == true;
    final state = DisabledMealState(
      mealId: mealId,
      mealName: payload['meal_name']?.toString() ?? 'Meal',
      categoryName: payload['category_name']?.toString(),
      orderId: payload['order_id']?.toString(),
      reason: payload['reason']?.toString() ?? 'نفذت الوجبة',
      isDisabled: isDisabled,
      updatedAt: DateTime.now(),
      source: 'kds',
    );

    if (isDisabled) {
      _disabledMeals[mealId] = state;
      _appendAudit(
        action: 'kds_disable',
        mealId: mealId,
        details: 'order=${state.orderId ?? '-'}',
      );
    } else {
      _disabledMeals.remove(mealId);
      _appendAudit(
        action: 'kds_enable',
        mealId: mealId,
        details: 'restored from kds',
      );
    }

    unawaited(_persistCache());
    notifyListeners();
  }

  bool isMealDisabled(String mealId) {
    final state = _disabledMeals[mealId];
    return state?.isDisabled == true;
  }

  DisabledMealState? getMealState(String mealId) => _disabledMeals[mealId];

  List<Product> suggestAlternatives(Product product, List<Product> source) {
    final normalizedCategory = product.category.trim().toLowerCase();
    final alternatives = source.where((candidate) {
      if (candidate.id == product.id) return false;
      if (isMealDisabled(candidate.id)) return false;
      if (!candidate.isActive) return false;
      return candidate.category.trim().toLowerCase() == normalizedCategory;
    }).toList();

    if (alternatives.length > 3) {
      return alternatives.sublist(0, 3);
    }
    return alternatives;
  }

  void _appendAudit({
    required String action,
    required String mealId,
    required String details,
  }) {
    _auditLog.insert(
      0,
      AvailabilityAuditEvent(
        action: action,
        mealId: mealId,
        details: details,
        at: DateTime.now(),
      ),
    );
    if (_auditLog.length > _maxAuditSize) {
      _auditLog.removeRange(_maxAuditSize, _auditLog.length);
    }
    unawaited(_persistAudit());
  }

  Future<void> _restoreCache() async {
    final cachedMeals = await _cache.get(_disabledMealsCacheKey);
    if (cachedMeals is List) {
      for (final raw in cachedMeals) {
        if (raw is! Map) continue;
        final payload = raw.map((k, v) => MapEntry(k.toString(), v));
        final state = DisabledMealState.fromJson(payload);
        if (state.mealId.isEmpty) continue;
        _disabledMeals[state.mealId] = state;
      }
    }

    final cachedAudit = await _cache.get(_auditCacheKey);
    if (cachedAudit is List) {
      for (final raw in cachedAudit) {
        if (raw is! Map) continue;
        final payload = raw.map((k, v) => MapEntry(k.toString(), v));
        _auditLog.add(AvailabilityAuditEvent.fromJson(payload));
      }
    }
  }

  Future<void> _persistCache() async {
    final payload = _disabledMeals.values.map((e) => e.toJson()).toList();
    await _cache.set(_disabledMealsCacheKey, payload,
        expiry: const Duration(days: 7));
  }

  Future<void> _persistAudit() async {
    final payload = _auditLog.map((e) => e.toJson()).toList();
    await _cache.set(_auditCacheKey, payload, expiry: const Duration(days: 7));
  }
}
