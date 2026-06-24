/// Thrown when an operation is attempted without the required authorization.
class UnauthorizedException implements Exception {
  const UnauthorizedException([this.reason = '']);
  final String reason;
  @override
  String toString() => reason.isEmpty
      ? 'UnauthorizedException'
      : 'UnauthorizedException: $reason';
}
