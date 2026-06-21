import 'package:flutter/foundation.dart';

/// Global router refresh signal.
///
/// go_router will re-run `redirect` only when its `refreshListenable` notifies.
/// Supabase auth state changes are not enough for our merchant gating, because
/// the merchant record is loaded asynchronously after sign-in / app restore.
///
/// AuthProvider calls [RouterRefresh.instance.ping] after it finishes loading
/// profile + merchant data so routing can react immediately.
class RouterRefresh extends ChangeNotifier {
  RouterRefresh._();

  static final RouterRefresh instance = RouterRefresh._();

  void ping() => notifyListeners();
}
