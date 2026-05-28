/// Pure policy object that answers "which pay methods are usable right
/// now?" given the per-branch enable map and the cashier's NearPay /
/// CDS state.
///
/// Lives in `lib/controllers/` so the same rules can be tested without
/// instantiating `_MainScreenState` or any Flutter widget. Previously
/// these checks lived inside `main_screen.payment.dart` (3,500-line
/// extension) where they mixed freely with UI state.
class PaymentMethodPolicy {
  /// Pay-methods the cashier flow recognizes. Anything outside this set
  /// is treated as "unknown / unsupported".
  static const supportedMethods = <String>{
    'cash',
    'card',
    'mada',
    'visa',
    'benefit',
    'stc',
    'bank_transfer',
    'wallet',
    'cheque',
    'petty_cash',
    'pay_later',
    'tabby',
    'tamara',
    'keeta',
    'my_fatoorah',
    'jahez',
    'talabat',
    'hunger_station',
  };

  /// Card-tier methods that NearPay owns end-to-end. When the branch is
  /// profile-NearPay-enabled AND the CDS isn't connected, these get
  /// suppressed because there's nowhere to render the card prompt.
  static const cardLikeMethods = <String>{
    'card',
    'mada',
    'visa',
    'benefit',
  };

  /// `true` when [normalizedMethod] should be offered to the cashier
  /// given the current branch + device state.
  ///
  /// - [enabledPayMethods] is the live per-method flag map.
  /// - [isProfileNearPayEnabled] indicates whether the merchant profile
  ///   has NearPay turned on.
  /// - [isCdsEnabled] indicates whether the customer display (which is
  ///   the only NearPay surface) is currently usable.
  static bool isMethodEnabledForInvoice({
    required String normalizedMethod,
    required Map<String, bool> enabledPayMethods,
    required bool isProfileNearPayEnabled,
    required bool isCdsEnabled,
  }) {
    if (normalizedMethod == 'card' &&
        isProfileNearPayEnabled &&
        !isCdsEnabled) {
      return false;
    }

    if (enabledPayMethods[normalizedMethod] == true) return true;

    // "card" is a virtual umbrella for the three branded variants.
    if (normalizedMethod == 'card') {
      return enabledPayMethods['mada'] == true ||
          enabledPayMethods['visa'] == true ||
          enabledPayMethods['benefit'] == true;
    }
    return false;
  }

  /// `true` if at least one supported method is currently usable.
  static bool hasAnyEnabledPayMethod({
    required Map<String, bool> enabledPayMethods,
    required bool isProfileNearPayEnabled,
    required bool isCdsEnabled,
  }) {
    for (final entry in enabledPayMethods.entries) {
      if (!supportedMethods.contains(entry.key)) continue;
      if (entry.value != true) continue;
      // Skip card-likes that are NearPay-only when CDS is unavailable.
      if (isProfileNearPayEnabled &&
          !isCdsEnabled &&
          cardLikeMethods.contains(entry.key)) {
        continue;
      }
      return true;
    }
    return false;
  }

  /// Returns a copy of [enabledPayMethods] with `pay_later` masked off
  /// — `pay_later` is a booking status, not a tender method, and must
  /// not appear in the tender dialog.
  static Map<String, bool> effectiveForTender(
      Map<String, bool> enabledPayMethods) {
    final effective = Map<String, bool>.from(enabledPayMethods);
    effective['pay_later'] = false;
    return effective;
  }
}
