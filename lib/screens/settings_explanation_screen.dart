import 'package:flutter/material.dart';

class SettingsExplanationScreen extends StatelessWidget {
  const SettingsExplanationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildSection(
            context,
            'Data Send Rate',
            'The amount of audio data sent per second affects streaming delay. '
            'If your network is slow or unstable, reducing the data rate can help prevent lag.',
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            'Sample Rate',
            'Sample rate (e.g., 22kHz, 16kHz) determines audio quality. '
            'Higher rates capture more detail but require more bandwidth. '
            'Lower rates reduce quality but improve streaming stability.',
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            'Compression',
            'The app uses 4-bit ADPCM compression (vs. 16-bit uncompressed). '
            'Compression reduces data size to 25% with minimal quality loss, '
            'helping prevent lag on slower networks.',
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }
} 