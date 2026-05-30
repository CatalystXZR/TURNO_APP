class RetryConfig {
  RetryConfig._();

  static const _maxAttempts = 3;
  static const _baseDelayMs = 500;

  static Future<T> withRetry<T>(
    Future<T> Function() operation, {
    int maxAttempts = _maxAttempts,
    int Function(int attempt)? delayMs,
    bool Function(Object error)? isRetryable,
  }) async {
    final delays = delayMs ?? (a) => _baseDelayMs * (1 << (a - 1));

    Object? lastError;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await operation();
      } catch (e) {
        lastError = e;
        if (attempt == maxAttempts) break;

        if (isRetryable != null && !isRetryable(e)) {
          break;
        }

        final waitMs = delays(attempt);
        if (waitMs > 0) {
          await Future.delayed(Duration(milliseconds: waitMs));
        }
      }
    }

    throw (lastError ?? Exception('Retry exhausted'));
  }

  static bool isNetworkError(Object e) {
    final text = e.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('timed out') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection closed') ||
        text.contains('connection refused') ||
        text.contains('no internet') ||
        text.contains('name not resolved');
  }
}
