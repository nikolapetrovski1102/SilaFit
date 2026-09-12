import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// A tiny loading/error/data union used by every feature controller that
/// fetches something from the API, so screens don't each reinvent
/// isLoading/error/data bookkeeping.
class ResourceState<T> {
  final bool isLoading;
  final String? error;
  final T? data;

  const ResourceState._(this.isLoading, this.error, this.data);

  const ResourceState.loading() : this._(true, null, null);
  const ResourceState.data(T value) : this._(false, null, value);
  const ResourceState.error(String message, {T? staleData})
      : this._(false, message, staleData);

  bool get hasData => data != null;
}

/// Renders a [ResourceState] with the right builder for its case. Centralizes
/// the loading spinner / error card so every feature screen looks the same.
class ResourceBuilder<T> extends StatelessWidget {
  final ResourceState<T> state;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;

  const ResourceBuilder(
      {super.key, required this.state, required this.builder, this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (state.hasData) return builder(context, state.data as T);
    if (state.error != null)
      return _ErrorCard(message: state.error!, onRetry: onRetry);
    return const _LoadingCard();
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 96),
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
              strokeWidth: 2.5, color: AppColors.accent),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _ErrorCard({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: 64, horizontal: AppSpacing.gutterMobile),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 28),
          const SizedBox(height: AppSpacing.sm),
          Text(message,
              textAlign: TextAlign.center, style: AppTypography.bodySm),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: onRetry,
              child: Text('RETRY',
                  style: AppTypography.labelCaps
                      .copyWith(color: AppColors.accent)),
            ),
          ],
        ],
      ),
    );
  }
}
