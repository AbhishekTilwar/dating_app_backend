import 'package:http/http.dart' as http;
import 'package:spark/core/constants/app_constants.dart';

/// Lightweight check that the Node API is running (same token as Firebase after login).
///
/// Render (and similar) free tiers cold-start after sleep; first request can take 30–90s.
/// We try a fast ping first, then a longer one so users don't see false "not reachable".
class BackendHealthService {
  BackendHealthService._();

  static final Uri _healthUri = Uri.parse('${AppConstants.apiBaseUrl}/health');

  static Future<bool> ping({
    Duration warmTimeout = const Duration(seconds: 8),
    Duration coldStartTimeout = const Duration(seconds: 90),
  }) async {
    for (final timeout in [warmTimeout, coldStartTimeout]) {
      try {
        final res = await http.get(_healthUri).timeout(timeout);
        if (res.statusCode == 200) return true;
      } catch (_) {
        // Retry with longer timeout (cold start) or give up
      }
    }
    return false;
  }
}
