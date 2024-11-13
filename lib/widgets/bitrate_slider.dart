import 'package:flutter/material.dart';

class BitrateSlider extends StatelessWidget {
  final int initialBitrate;
  final Function(int) onBitrateChanged;

  const BitrateSlider({
    Key? key,
    required this.initialBitrate,
    required this.onBitrateChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final List<int> bitrates = [8, 16, 32, 64, 128];
    final int initialIndex = bitrates.indexOf(initialBitrate);

    return Column(
      children: [
        Slider(
          value: initialIndex.toDouble(),
          min: 0,
          max: (bitrates.length - 1).toDouble(),
          divisions: bitrates.length - 1,
          label: '${bitrates[initialIndex]} kbps',
          onChanged: (double value) {
            onBitrateChanged(bitrates[value.round()]);
          },
        ),
        Text('Bitrate: $initialBitrate kbps'),
      ],
    );
  }
} 