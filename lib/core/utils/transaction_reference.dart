/// Utilities for rendering human-friendly transaction references.
///
/// The backend reference can be long (UUID-like). In lists, we display a short
/// variant while keeping enough characters to identify the transaction.
library;

/// Returns a shortened transaction reference for UI display.
///
/// Examples:
/// - `TXN-c9a20a96969c47049a148cd4df0d3` -> `TXN-c9a2…f0d3`
/// - `c9a20a96969c47049a148cd4df0d3` -> `c9a20a…f0d3`
String shortenTransactionReference(String reference, {int head = 4, int tail = 4}) {
  final ref = reference.trim();
  if (ref.isEmpty) return ref;

  const prefix = 'TXN-';
  if (ref.startsWith(prefix)) {
    final rest = ref.substring(prefix.length);
    if (rest.length <= head + tail + 1) return ref;
    return '$prefix${rest.substring(0, head)}…${rest.substring(rest.length - tail)}';
  }

  if (ref.length <= head + tail + 1) return ref;
  return '${ref.substring(0, head)}…${ref.substring(ref.length - tail)}';
}
