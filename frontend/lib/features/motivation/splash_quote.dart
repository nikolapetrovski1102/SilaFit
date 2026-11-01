import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'motivational_quotes_repository.dart';

/// A motivational line at the bottom of the splash screen that fades from
/// one line to the next for as long as the splash is up.
///
/// Paints straight from the device's saved set (see
/// [MotivationalQuotesRepository]) and refreshes it from the server behind
/// the scenes; a fresh set is used for the following lines and saved for
/// the next launch, so offline launches still get the latest lines seen.
class SplashQuote extends StatefulWidget {
  const SplashQuote({super.key});

  @override
  State<SplashQuote> createState() => _SplashQuoteState();
}

class _SplashQuoteState extends State<SplashQuote> {
  /// Time each line stays up - enough to read a short sentence.
  static const _hold = Duration(milliseconds: 3200);
  static const _fade = Duration(milliseconds: 600);

  final _random = math.Random();
  List<MotivationalQuote> _quotes = const [];
  MotivationalQuote? _current;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final repository =
        MotivationalQuotesRepository(context.read<ApiClient>());
    repository.cached().then((quotes) {
      if (!mounted) return;
      setState(() {
        _quotes = quotes;
        _current = _pick();
      });
      _timer = Timer.periodic(_hold, (_) {
        if (mounted) setState(() => _current = _pick());
      });
    });
    repository.refresh().then((fresh) {
      if (fresh != null && mounted) _quotes = fresh;
    });
  }

  /// A random line, never the one already showing.
  MotivationalQuote? _pick() {
    if (_quotes.isEmpty) return null;
    if (_quotes.length == 1) return _quotes.first;
    MotivationalQuote next;
    do {
      next = _quotes[_random.nextInt(_quotes.length)];
    } while (next.text == _current?.text);
    return next;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quote = _current;
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : _fade,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.bottomCenter,
        children: [...previous, if (current != null) current],
      ),
      child: quote == null
          ? const SizedBox.shrink(key: ValueKey('none'))
          : Column(
              key: ValueKey(quote.text),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  quote.text,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyLg
                      .copyWith(color: AppColors.onSurface, height: 1.4),
                ),
                if (quote.author != null && quote.author!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '- ${quote.author}',
                    textAlign: TextAlign.center,
                    style: AppTypography.labelSm
                        .copyWith(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ],
            ),
    );
  }
}
