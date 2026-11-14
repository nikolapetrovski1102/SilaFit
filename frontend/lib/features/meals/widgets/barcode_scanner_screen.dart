import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../l10n/l10n.dart';

/// Full-screen camera that reads one package barcode (EAN-13/8, UPC-A/E) and
/// returns its digits, or null if the user backed out. Decoding runs on the
/// device; "Type it" covers a crumpled or unreadable code.
Future<String?> showBarcodeScanner(BuildContext context) {
  return Navigator.of(context).push<String>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => const _BarcodeScannerScreen(),
  ));
}

/// The digits of a retail barcode, or null: what the server accepts too.
String? cleanBarcode(String? raw) {
  final digits = raw?.replaceAll(RegExp(r'[\s-]'), '') ?? '';
  return RegExp(r'^\d{8,14}$').hasMatch(digits) ? digits : null;
}

class _BarcodeScannerScreen extends StatefulWidget {
  const _BarcodeScannerScreen();

  @override
  State<_BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<_BarcodeScannerScreen> {
  final _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish(String code) {
    if (_done) return;
    _done = true;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(code);
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final code = cleanBarcode(barcode.rawValue);
      if (code != null) {
        _finish(code);
        return;
      }
    }
  }

  Future<void> _typeIt() async {
    await _controller.stop();
    if (!mounted) return;
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _TypeBarcodeDialog(),
    );
    if (!mounted) return;
    if (code != null) {
      _finish(code);
    } else {
      await _controller.start();
    }
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    if (mounted) setState(() => _torchOn = !_torchOn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        final pad = MediaQuery.paddingOf(context);
        // Fixed bands the scan window must never reach into: the close button
        // on top, the hint plus the action buttons at the bottom.
        const topBar = 56.0;
        const hintBand = 56.0;
        const bottomBar = 112.0;
        final freeTop = pad.top + topBar;
        final freeBottom = size.height - pad.bottom - bottomBar - hintBand;

        // A wide, short window: barcodes are horizontal strips, and a smaller
        // window keeps a neighbouring product's code from being read instead.
        // Shrinks on short screens rather than overlapping the controls.
        var width =
            (size.width - 2 * AppSpacing.xxl).clamp(160.0, 340.0).toDouble();
        var height = width * 0.6;
        final room = freeBottom - freeTop - 2 * AppSpacing.md;
        if (height > room) {
          height = room.clamp(80.0, height).toDouble();
          width = (height / 0.6).clamp(0.0, width).toDouble();
        }
        final window = Rect.fromCenter(
          center: Offset(size.width / 2, (freeTop + freeBottom) / 2),
          width: width,
          height: height,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              scanWindow: window,
              errorBuilder: (context, error) => _ScannerError(
                permissionDenied:
                    error.errorCode == MobileScannerErrorCode.permissionDenied,
                onTypeIt: _typeIt,
              ),
            ),
            IgnorePointer(
              child: CustomPaint(
                  painter: _WindowPainter(window, AppColors.accent)),
            ),
            Positioned(
              top: pad.top + AppSpacing.xs,
              left: AppSpacing.sm,
              child: _CircleButton(
                icon: Icons.close_rounded,
                tooltip: tr('Close'),
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned(
              left: AppSpacing.marginMobile,
              right: AppSpacing.marginMobile,
              top: window.bottom + AppSpacing.md,
              child: Text(
                tr('Point the camera at the barcode'),
                textAlign: TextAlign.center,
                style: AppTypography.bodyMd.copyWith(color: Colors.white),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: pad.bottom + AppSpacing.lg,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _LabeledAction(
                    icon: _torchOn
                        ? Icons.flash_on_rounded
                        : Icons.flash_off_rounded,
                    label: tr('Flashlight'),
                    active: _torchOn,
                    onTap: _toggleTorch,
                  ),
                  _LabeledAction(
                    icon: Icons.keyboard_alt_outlined,
                    label: tr('Type the number'),
                    onTap: _typeIt,
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}

/// A round camera control with its name under it.
class _LabeledAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _LabeledAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? AppColors.accent
                    : Colors.white.withValues(alpha: 0.16),
              ),
              child: Icon(icon,
                  color: active ? Colors.black : Colors.white, size: 26),
            ),
            const SizedBox(height: AppSpacing.xs),
            ExcludeSemantics(
              child: Text(label,
                  style: AppTypography.labelSm.copyWith(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dims everything outside the scan window and draws its corners.
class _WindowPainter extends CustomPainter {
  final Rect window;
  final Color color;

  _WindowPainter(this.window, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(18);
    final hole = RRect.fromRectAndRadius(window, radius);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(hole),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    const arm = 28.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final r = radius.x;
    final w = window;
    final corners = Path()
      // top-left
      ..moveTo(w.left, w.top + arm)
      ..lineTo(w.left, w.top + r)
      ..arcToPoint(Offset(w.left + r, w.top), radius: radius)
      ..lineTo(w.left + arm, w.top)
      // top-right
      ..moveTo(w.right - arm, w.top)
      ..lineTo(w.right - r, w.top)
      ..arcToPoint(Offset(w.right, w.top + r), radius: radius)
      ..lineTo(w.right, w.top + arm)
      // bottom-right
      ..moveTo(w.right, w.bottom - arm)
      ..lineTo(w.right, w.bottom - r)
      ..arcToPoint(Offset(w.right - r, w.bottom), radius: radius)
      ..lineTo(w.right - arm, w.bottom)
      // bottom-left
      ..moveTo(w.left + arm, w.bottom)
      ..lineTo(w.left + r, w.bottom)
      ..arcToPoint(Offset(w.left, w.bottom - r), radius: radius)
      ..lineTo(w.left, w.bottom - arm);
    canvas.drawPath(corners, paint);
  }

  @override
  bool shouldRepaint(_WindowPainter old) =>
      old.window != window || old.color != color;
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _CircleButton(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _ScannerError extends StatelessWidget {
  final bool permissionDenied;
  final VoidCallback onTypeIt;

  const _ScannerError({required this.permissionDenied, required this.onTypeIt});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white, size: 40),
              const SizedBox(height: AppSpacing.md),
              Text(
                permissionDenied
                    ? tr('Allow camera access in Settings to scan barcodes.')
                    : tr("The camera couldn't start."),
                textAlign: TextAlign.center,
                style: AppTypography.bodyMd.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.md),
              if (permissionDenied)
                TextButton(
                  onPressed: openAppSettings,
                  child: Text(tr('Open Settings'),
                      style: AppTypography.bodyMd
                          .copyWith(color: AppColors.accent)),
                ),
              TextButton(
                onPressed: onTypeIt,
                child: Text(tr('Type the number instead'),
                    style:
                        AppTypography.bodyMd.copyWith(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeBarcodeDialog extends StatefulWidget {
  const _TypeBarcodeDialog();

  @override
  State<_TypeBarcodeDialog> createState() => _TypeBarcodeDialogState();
}

class _TypeBarcodeDialogState extends State<_TypeBarcodeDialog> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final code = cleanBarcode(_text.text);
    if (code == null) {
      setState(() => _error = tr('A barcode is 8 to 14 digits.'));
      return;
    }
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainer,
      title: Text(tr('Barcode number'), style: AppTypography.headlineSm),
      content: TextField(
        controller: _text,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 14,
        style: AppTypography.bodyLg,
        decoration: InputDecoration(
          hintText: '5310000000000',
          errorText: _error,
          counterText: '',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        TextButton(onPressed: _submit, child: Text(tr('Look up'))),
      ],
    );
  }
}
