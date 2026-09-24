import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/slim_action_row.dart';
import '../../auth/auth_controller.dart';
import '../../plans/plans_controller.dart';
import '../../plans/plans_repository.dart';
import '../../plans/plans_screen.dart';
import '../../progress/analytics_models.dart';
import '../../progress/analytics_repository.dart';
import '../../progress/monthly_overview_screen.dart';
import '../../settings/ai_consent_gate.dart';
import '../today_controller.dart';

/// Home's paid recap entry point. Uses the actual subscription, independently
/// of the development analytics bypass, and never substitutes monthly for weekly.
class AiInsightsTeaserCard extends StatefulWidget {
  final double scale;
  const AiInsightsTeaserCard({super.key, this.scale = 1});

  @override
  State<AiInsightsTeaserCard> createState() => _AiInsightsTeaserCardState();
}

class _AiInsightsTeaserCardState extends State<AiInsightsTeaserCard>
    with WidgetsBindingObserver {
  Object? _session;
  Object? _dashboard;
  int? _purchaseRevision;
  int _request = 0;
  bool _loading = true;
  String? _plan;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<AuthController>().session;
    final dashboard = context.watch<TodayController>().state.data;
    final revision = context.watch<PlansController>().purchaseRevision;
    if (_purchaseRevision != revision ||
        _session != session ||
        _dashboard != dashboard) {
      _session = session;
      _dashboard = dashboard;
      _purchaseRevision = revision;
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    _request++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    final plans = context.read<PlansRepository>();
    setState(() {
      _loading = true;
      _plan = null;
      _message = null;
    });
    String? plan;
    String? message;
    try {
      plan = await plans.getActivePlanCode();
    } on ApiException catch (e) {
      message = e.isForbidden
          ? 'Access changed. Tap to check your subscription'
          : 'Could not check your subscription. Tap to retry';
    } catch (_) {
      message = 'Could not check your subscription. Tap to retry';
    }
    if (!mounted || request != _request) return;
    setState(() {
      _loading = false;
      _plan = plan;
      _message = message;
    });
  }

  Future<void> _openReview() async {
    final plan = _plan;
    if (plan != 'PRO' && plan != 'ADVANCED') {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const PlansScreen()));
      if (mounted) await _load();
      return;
    }

    if (!await AiConsentGate.ensure(context) || !mounted) return;

    final request = ++_request;
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final analytics = context.read<AnalyticsRepository>();
      final AnalyticsRecap report = plan == 'ADVANCED'
          ? await analytics.getWeekly()
          : await analytics.getMonthly();
      if (!mounted || request != _request) return;
      setState(() => _loading = false);
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (routeContext) => MonthlyOverviewScreen(
          analytics: report,
          onDone: () => Navigator.of(routeContext).pop(),
        ),
      ));
    } on ApiException catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _message = e.isInsufficientData
            ? 'Log more workouts and meals to prepare your review'
            : e.isAiConsentRequired
                ? 'Allow AI data sharing to see your review'
                : e.isForbidden
                ? 'Access changed. Tap to check your subscription'
                : 'Could not load your review. Tap to retry';
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _message = 'Could not load your review. Tap to retry';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final paid = _plan == 'PRO' || _plan == 'ADVANCED';
    final weekly = _plan == 'ADVANCED';
    return SlimActionRow(
      icon: paid ? Icons.auto_awesome_rounded : Icons.lock_outline_rounded,
      iconColor: AppColors.secondary,
      iconBackground: AppColors.secondary.withValues(alpha: 0.16),
      label: _loading
          ? 'AI REVIEW'
          : weekly
              ? 'WEEKLY AI REVIEW'
              : paid
                  ? 'MONTHLY AI REVIEW'
                  : 'AI TRAINING REVIEWS',
      value: _loading
          ? 'Checking your subscription…'
          : _message ??
              (weekly
                  ? 'Open your weekly overview'
                  : paid
                      ? 'Open your monthly overview'
                      : 'Pro: monthly · Advanced: weekly'),
      scale: widget.scale,
      borderColor: AppColors.secondary.withValues(alpha: 0.3),
      trailing: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Text(
              paid
                  ? _plan!
                  : _message != null
                      ? 'RETRY'
                      : 'UNLOCK',
              style: AppTypography.labelCaps.copyWith(
                  color: AppColors.secondary, fontSize: 9 * widget.scale)),
      onTap: _loading
          ? null
          : _message != null && !paid
              ? _load
              : _openReview,
    );
  }
}
