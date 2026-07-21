import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _didDetect = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDetection(BarcodeCapture capture) {
    if (_didDetect) return;

    final rawValue =
        capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (rawValue == null || rawValue.trim().isEmpty) return;

    _didDetect = true;
    Navigator.pop(context, rawValue.trim());
  }

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Theme(
          data: AppTheme.company(companyTheme),
          child: Scaffold(
            backgroundColor: companyTheme.backgroundColor,
            appBar: AppBar(
              backgroundColor: companyTheme.surfaceColor,
              foregroundColor: companyTheme.inkColor,
              iconTheme: IconThemeData(color: companyTheme.inkColor),
              title: Text(
                'Scan Food Barcode',
                style: TextStyle(
                  color: companyTheme.inkColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            body: Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _handleDetection,
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 32,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Text(
                      'Point your camera at a packaged food barcode to auto-fill its calories and macros.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
