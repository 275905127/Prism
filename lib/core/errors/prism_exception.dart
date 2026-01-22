// lib/core/errors/prism_exception.dart
class PrismException implements Exception {
  final String userMessage;
  final String? debugMessage;
  final Object? cause;

  const PrismException({
    required this.userMessage,
    this.debugMessage,
    this.cause,
  });

  @override
  String toString() => debugMessage ?? userMessage;
}
