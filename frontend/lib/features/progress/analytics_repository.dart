import '../../core/api/api_client.dart';
import 'analytics_models.dart';

class AnalyticsRepository {
  final ApiClient _client;

  AnalyticsRepository(this._client);

  Future<MonthlyAnalytics> getMonthly({int? year, int? month, bool refresh = false}) =>
      _client.get('/analytics/monthly', MonthlyAnalytics.fromJson, query: {
        if (year != null) 'year': '$year',
        if (month != null) 'month': '$month',
        if (refresh) 'refresh': 'true',
      });
}
