class NearpayException implements Exception {
  final String message;

  NearpayException(this.message);

  @override
  String toString() => "NearpayException: $message";
}
