import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/platform/screen_security.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// A trainer's PDF, read-only, in a locked WebView.
///
/// The page (served by the API) draws each page as an image with the reader's
/// name burned in, so there's no text to select or file to save. On top of
/// that this screen:
/// * holds [ScreenSecurity] for as long as it's open (the app is already
///   locked app-wide; the extra hold keeps documents locked even if that
///   changes) and warns after an iOS screenshot attempt;
/// * never leaves the viewer's own address - no links out, no "open in
///   browser", no downloads;
/// * clears the WebView's cache and storage when it closes.
///
/// [viewerUrl] carries a short-lived ticket, so the screen is always opened
/// with a freshly minted URL.
class SecureDocumentScreen extends StatefulWidget {
  final String title;
  final String viewerUrl;
  final String? trainerName;

  const SecureDocumentScreen({
    super.key,
    required this.title,
    required this.viewerUrl,
    this.trainerName,
  });

  @override
  State<SecureDocumentScreen> createState() => _SecureDocumentScreenState();
}

class _SecureDocumentScreenState extends State<SecureDocumentScreen> {
  late final WebViewController _controller;
  late final Uri _origin;
  StreamSubscription<void>? _screenshotSub;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    ScreenSecurity.enable();
    _screenshotSub =
        ScreenSecurity.screenshots.listen((_) => _warnScreenshot());

    _origin = Uri.parse(widget.viewerUrl);
    _controller = WebViewController()
      // pdf.js renders the pages; the page itself has no other script.
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0E0F12))
      ..enableZoom(true)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _isLoading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _isLoading = false);
        },
        onWebResourceError: (error) {
          if (!mounted || error.isForMainFrame != true) return;
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
        },
        // Stay on the viewer: anything else (a link inside the PDF, a
        // redirect elsewhere) is dropped rather than opened.
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          final sameOrigin = uri != null &&
              uri.scheme == _origin.scheme &&
              uri.host == _origin.host &&
              uri.port == _origin.port &&
              uri.path.startsWith('/api/documents/');
          return sameOrigin
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
      ))
      ..loadRequest(_origin);
  }

  @override
  void dispose() {
    _screenshotSub?.cancel();
    ScreenSecurity.disable();
    // Nothing of the document should outlive the screen on disk.
    _controller.clearCache();
    _controller.clearLocalStorage();
    super.dispose();
  }

  void _warnScreenshot() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.no_photography_outlined, color: AppColors.error),
        title: const Text('Screenshots are off here'),
        content: Text(
          'This document is a personal copy from '
          '${widget.trainerName ?? 'your trainer'}. Every page carries your '
          'name, so please keep it to yourself.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0F12),
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(widget.title,
            style: AppTypography.headlineSm,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Tooltip(
              message: 'Protected: no screenshots, no sharing',
              child: Icon(Icons.lock_outline_rounded,
                  size: 20, color: AppColors.onSurfaceVariant),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_hasError)
            Positioned.fill(
              child: ColoredBox(
                color: AppColors.background,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wifi_off_rounded,
                            size: 40, color: AppColors.onSurfaceVariant),
                        const SizedBox(height: AppSpacing.sm),
                        Text('The document could not be loaded.',
                            textAlign: TextAlign.center,
                            style: AppTypography.headlineSm),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Check your connection, then close it and open it again.',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySm
                              .copyWith(color: AppColors.onSurfaceVariant),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                ),
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
