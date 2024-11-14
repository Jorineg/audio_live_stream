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
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Text('Connection Issues?'),
                      content: const Text(
                        'Please check the following:\n\n'
                        '1. Ensure that you and your listeners are connected to the '
                        'same network.\n\n'
                        '2. If you have your mobile hotspot enabled, the QR code will '
                        'show your hotspot\'s IP address. You have two options:\n'
                        '   • Ask listeners to join your hotspot network, or\n'
                        '   • Disable your hotspot to use the WiFi network instead\n\n'
                        '3. Some WiFi networks (especially public or corporate networks) '
                        'have security settings that prevent devices from communicating '
                        'with each other. If you\'re having trouble with WiFi, using your '
                        'phone\'s mobile hotspot might work better.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('OK'),
                        ),
                      ],
                    );
                  },
                );
              },
              child: const Text(
                'Connection issues?',
                style: TextStyle(
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
