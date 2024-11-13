import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:ui' as ui;

class QRCodeScreen extends StatelessWidget {
  final String serverAddress;

  const QRCodeScreen({super.key, required this.serverAddress});

  Future<void> _shareQRCode(BuildContext context) async {
    try {
      final qrPainter = QrPainter(
        data: serverAddress,
        version: QrVersions.auto,
        gapless: true,
        color: Colors.black,
        emptyColor: Colors.white,
      );

      final image = await qrPainter.toImage(2048);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        throw Exception('Failed to generate QR code image');
      }

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/qr_code.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'QR Code for Audio Stream',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share QR code: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Connect to Audio',
          style: TextStyle(
            fontSize: 24,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const SizedBox(height: 24),
            QrImageView(
              data: serverAddress,
              version: QrVersions.auto,
              size: MediaQuery.of(context).size.width - 32,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.qr_code),
                  label: const Text('Share QR Code'),
                  onPressed: () => _shareQRCode(context),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.link),
                  label: const Text('Share Link'),
                  onPressed: () {
                    Share.share(serverAddress);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
} 