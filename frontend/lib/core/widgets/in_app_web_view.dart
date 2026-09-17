import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// In-app browser for the app's own hosted pages (Support, Privacy Policy), so
/// tapping those Settings rows keeps the user inside the app instead of
/// handing them off to Safari/Chrome.
///
/// Only http(s) navigations load in the WebView; any other scheme (`mailto:`,
/// `tel:`, a custom app link) is passed to the OS, the same way a system
/// in-app browser behaves. A top-level load failure shows a retry/fallback
/// view rather than a dead blank page, and the toolbar always offers "open in
/// browser" as an escape hatch.
class InAppWebViewScreen extends StatefulWidget {
  const InAppWebViewScreen({
    super.key,
    required this.title,
    required this.url,
  });

  final String title;
  final String url;

  @override
  State<InAppWebViewScreen> createState() => _InAppWebViewScreenState();
}

class _InAppWebViewScreenState extends State<InAppWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.background)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (!mounted) return;
          setState(() {
            _isLoading = true;
            _hasError = false;
          });
        },
        onPageFinished: (_) {
          if (!mounted) return;
          setState(() => _isLoading = false);
        },
        onWebResourceError: (error) {
          // Only a failed *top-level* navigation should take over the screen -
          // a blocked image/ad subresource must not blank the whole page.
          if (!mounted || error.isForMainFrame != true) return;
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null ||
              (uri.scheme != 'http' && uri.scheme != 'https')) {
            // Hand non-web schemes to the OS and keep the WebView where it is.
            if (uri != null) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _openInBrowser() => launchUrl(
        Uri.parse(widget.url),
        mode: LaunchMode.externalApplication,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.title, style: AppTypography.headlineSm),
        actions: [
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(Icons.open_in_browser_rounded),
            onPressed: _openInBrowser,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Kept mounted even while the error overlay is up, so the controller
          // stays attached and "Try again" can re-use it.
          WebViewWidget(controller: _controller),
          if (_hasError)
            Positioned.fill(
              child: _WebErrorView(
                onRetry: () {
                  setState(() {
                    _hasError = false;
                    _isLoading = true;
                  });
                  _controller.reload();
                },
                onOpenInBrowser: _openInBrowser,
              ),
            ),
          if (_isLoading && !_hasError)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }
}

class _WebErrorView extends StatelessWidget {
  const _WebErrorView({
    required this.onRetry,
    required this.onOpenInBrowser,
  });

  final VoidCallback onRetry;
  final VoidCallback onOpenInBrowser;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded,
                  size: 40, color: AppColors.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('This page could not be loaded.',
                  textAlign: TextAlign.center, style: AppTypography.headlineSm),
              const SizedBox(height: 6),
              Text(
                'Check your connection and try again.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
              TextButton(
                onPressed: onOpenInBrowser,
                child: const Text('Open in browser'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
