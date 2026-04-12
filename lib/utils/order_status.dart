int? parseOrderStatus(dynamic status) {
  if (status == null) return null;
  if (status is int) return status;
  if (status is num) return status.toInt();
  return int.tryParse(status.toString().trim());
}

bool isOrderLocked(int status) =>
    status == 3 || status == 5 || status == 6 || status == 7 || status == 8;

bool isOrderLockedValue(dynamic status) {
  final parsed = parseOrderStatus(status);
  if (parsed == null) return false;
  return isOrderLocked(parsed);
}

bool isNewOrderStatus(dynamic status) => parseOrderStatus(status) == 1;
