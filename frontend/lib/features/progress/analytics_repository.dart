import '../../core/api/api_client.dart';
import 'analytics_models.dart';

class AnalyticsRepository {
  final ApiClient _client;

  AnalyticsRepository(this._client);

  Future<MonthlyAnalytics> getMonthly(
          {int? year, int? month, bool refresh = false}) =>
      _client.get('/analytics/monthly', MonthlyAnalytics.fromJson, query: {
        if (year != null) 'year': '$year',
        if (month != null) 'month': '$month',
        if (refresh) 'refresh': 'true',
      });

  /// The ADVANCED-only weekly recap. A Pro-tier caller gets a 403 (mapped to
  /// `requiresUpgrade`); the weekly controller keeps that distinct from the
  /// monthly one so the Progress screen can show an Advanced-specific upsell.
  Future<WeeklyAnalytics> getWeekly(
          {int? year, int? week, bool refresh = false}) =>
      _client.get('/analytics/weekly', WeeklyAnalytics.fromJson, query: {
        if (year != null) 'year': '$year',
        if (week != null) 'week': '$week',
        if (refresh) 'refresh': 'true',
      });
}
