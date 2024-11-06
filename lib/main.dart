import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'audio_streaming_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WiFi Audio Stream',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('WiFi Audio Stream'),
        ),
        body: const StreamingControl(),
      ),
    );
  }
}

class StreamingControl extends StatefulWidget {
  const StreamingControl({super.key});

  @override
  _StreamingControlState createState() => _StreamingControlState();
}

class _StreamingControlState extends State<StreamingControl> {
  final AudioStreamingService _streamingService = AudioStreamingService();
  bool _isStreaming = false;
  String _ipAddress = 'Lade...';
  String _hostname = 'Lade...';
  String _serverAddressIP = '';
  String _serverAddressHostname = '';
  int _connectedClients = 0;
  String _mdnsName = 'audiostream';
  String? _errorMessage;
  bool _serverStarting = true;
  int _selectedBitrate = 64; // Default bitrate
  bool _bitrateChangeNotification = false;
  List<int> _audioSamples = [];
  double _latency = 0.0;
  double _emaLatency = 0.0;
  Timer? _timer;

  double _sampleRate = 16000; // Default sample rate
  bool _adpcmCompression = false; // Default ADPCM compression state

  static const platform = MethodChannel('com.jorin.audio_live_stream/hostname');

  @override
  void initState() {
    super.initState();
    _initializeStreaming();
    _getIpAddress();
    _getDeviceName();

    List<int> _processAudioSamples(Uint8List data) {
      final audioData = ByteData.sublistView(data);
      List<int> samples = [];
      for (int i = 0; i < audioData.lengthInBytes; i += 2) {
        int sample = audioData.getInt16(i, Endian.little);
        samples.add(sample);
      }
      int desiredSampleCount = 360;
      int step = max(1, samples.length ~/ desiredSampleCount);
      List<int> downsampled = [];
      for (int i = 0; i < samples.length; i += step) {
        downsampled.add(samples[i]);
      }
      return downsampled;
    }

    _streamingService.audioSampleStream.listen((data) {
      setState(() {
        _audioSamples = _processAudioSamples(data);
      });
    });

    _streamingService.webServer.onClientCountChanged = (count) {
      setState(() {
        _connectedClients = count;
      });
      print('Anzahl verbundener Clients aktualisiert: $_connectedClients');
    };

    _streamingService.webServer.latencyStream.listen((latency) {
      setState(() {
        _emaLatency = latency;
      });
    });

    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _latency = _emaLatency;
      });
    });
  }

  Future<void> _initializeStreaming() async {
    await _streamingService.initialize();
    await _startServer();
  }

  Future<void> _startServer() async {
    setState(() {
      _serverStarting = true;
    });
    try {
      await _streamingService.startServer(_mdnsName);
      final serverPort = _streamingService.webServer.server?.port;
      setState(() {
        _serverAddressIP = 'http://$_ipAddress:$serverPort';
        _serverAddressHostname = 'http://${_mdnsName}.local:$serverPort';
        _serverStarting = false;
      });
    } catch (e) {
      print('Fehler beim Starten des Servers: $e');
      if (mounted) {
        setState(() {
          _serverStarting = false;
          _errorMessage = 'Fehler beim Starten des Servers: $e';
        });
      }
    }
  }

  Future<void> _stopServer() async {
    await _streamingService.stopStreaming();
    setState(() {
      _isStreaming = false;
    });
    await _streamingService.stopServer();
    setState(() {
      _serverAddressIP = '';
      _serverAddressHostname = '';
    });
  }

  Future<void> _getIpAddress() async {
    try {
      final ipAddress = await NetworkInfo().getWifiIP();
      setState(() {
        _ipAddress = ipAddress ?? 'Unbekannt';
      });
    } catch (e) {
      print('Fehler beim Abrufen der IP-Adresse: $e');
      setState(() {
        _ipAddress = 'Fehler';
      });
    }
  }

  Future<void> _getDeviceName() async {
    String? deviceName;
    if (Platform.isAndroid) {
      try {
        deviceName = await platform.invokeMethod('getHostName');
        print('Device Name: $deviceName');
      } on PlatformException catch (e) {
        print("Failed to get hostname: '${e.message}'.");
        deviceName = null;
      }
    } else if (Platform.isIOS) {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      deviceName = iosInfo.name;
    }
    setState(() {
      _hostname = deviceName ?? 'audiostream';
      _mdnsName = _processMDNSName(_hostname);
    });
  }

  String _processMDNSName(String name) {
    return name.toLowerCase().replaceAll(RegExp(r'\s+'), '-');
  }

  void _startStreaming() {
    if (_serverStarting) {
      showMessage('Bitte warten Sie, der Server startet noch');
      return;
    }
    setState(() {
      _isStreaming = true;
    });
    _startAndroidForegroundService();
    _streamingService.startStreaming();
  }

  void _stopStreaming() {
    _streamingService.stopStreaming();
    _stopAndroidForegroundService();
    setState(() {
      _isStreaming = false;
    });
  }

  void showMessage(String message) {
    setState(() {
      _errorMessage = message;
    });
    Future.delayed(Duration(seconds: 3), () {
      if (_errorMessage == message) {
        setState(() {
          _errorMessage = null;
        });
      }
    });
  }

  void _onBitrateChanged(int newBitrate) {
    setState(() {
      _selectedBitrate = newBitrate;
      if (_isStreaming) {
        _bitrateChangeNotification = true;
        showMessage('Bitrate will be applied on next mic toggle');
      } else {
        _streamingService.setBitrate(newBitrate);
      }
    });
  }

  void _toggleStreaming() {
    if (_serverStarting) {
      showMessage('Please wait, the server is still starting');
      return;
    }
    setState(() {
      _isStreaming = !_isStreaming;
      if (_isStreaming) {
        _startStreaming();
      } else {
        _stopStreaming();
        _audioSamples = [];
      }
      if (_bitrateChangeNotification) {
        _streamingService.setBitrate(_selectedBitrate);
        _bitrateChangeNotification = false;
      }
    });
  }

  void _onSampleRateChanged(double newSampleRate) {
    setState(() {
      _sampleRate = newSampleRate;
      _streamingService.setSampleRate(newSampleRate);
    });
  }

  void _onAdpcmCompressionChanged(bool newAdpcmCompression) {
    setState(() {
      _adpcmCompression = newAdpcmCompression;
      _streamingService.setAdpcmCompression(newAdpcmCompression);
    });
  }

  @override
  Widget build(BuildContext context) {
    double dataSendRate =
        _streamingService.getCurrentDataSendRate() * _connectedClients;
    String dataSendRateText = dataSendRate >= 1000
        ? '${(dataSendRate / 1000).toStringAsFixed(2)} Mbps'
        : '${dataSendRate.toStringAsFixed(0)} kbps';
    Color dataSendRateColor = dataSendRate > 10000 ? Colors.red : Colors.grey;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Connected Clients: $_connectedClients',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          // const SizedBox(height: 20),
          // SizedBox(height: MediaQuery.of(context).size.height * 0.1),
          Center(
            child: GestureDetector(
              onTap: _toggleStreaming,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: Size(200, 200),
                    painter: CircularWaveformPainter(
                      samples: _audioSamples,
                      isMicMuted: !_isStreaming,
                    ),
                  ),
                  StreamBuilder<double>(
                    stream: _streamingService.micLevelStream,
                    builder: (context, snapshot) {
                      double micLevel = snapshot.data ?? 0.0;
                      double iconSize = 100.0;
                      Color iconColor;
                      IconData iconData;
                      if (_serverStarting) {
                        iconColor = Colors.grey;
                        iconData = Icons.mic_off;
                      } else {
                        micLevel = micLevel / 100;
                        double saturation = (micLevel * 40 + 60).clamp(60, 100);
                        double hue = (130 - micLevel * 170).clamp(0, 360);
                        Color color =
                            HSLColor.fromAHSL(1, hue, saturation / 100, 0.5)
                                .toColor();
                        iconColor = _isStreaming ? color : Colors.grey;
                        iconData = _isStreaming ? Icons.mic : Icons.mic_off;
                      }
                      return Icon(
                        iconData,
                        size: iconSize,
                        color: iconColor,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          // const SizedBox(height: 16),
          Text(
            _serverStarting
                ? 'Server is starting...'
                : _isStreaming
                    ? 'Tap to mute'
                    : 'Tap to activate microphone',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          const Spacer(),
          const SizedBox(height: 20),
          Text(
            _connectedClients == 0 || _latency > 2000
                ? 'Latency: -'
                : 'Latency: ${_latency.toStringAsFixed(0).padLeft(4, ' ')} ms',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _latency > 500 ? Colors.red : Colors.grey,
            ),
          ),
          Text(
            'Send Rate: $dataSendRateText',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: dataSendRateColor,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Sample Rate: ${_sampleRate.toInt()} Hz'),
              Row(
                children: [
                  Checkbox(
                    value: _adpcmCompression,
                    onChanged: (bool? value) {
                      if (value != null) {
                        _onAdpcmCompressionChanged(value);
                      }
                    },
                  ),
                  Text('Compression'),
                ],
              ),
            ],
          ),
          Slider(
            value: _sampleRate,
            min: 8000,
            max: 22000,
            divisions: 14,
            label: '${_sampleRate.toInt()} Hz',
            onChanged: (double value) {
              _onSampleRateChanged(value);
            },
          ),
          // const SizedBox(height: 20),
          _serverStarting
              ? const Center(
                  child: Text('Server is starting...',
                      textAlign: TextAlign.center))
              : Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text(
                          'Server Address:',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _serverAddressIP,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.share),
                              onPressed: () {
                                Share.share(_serverAddressIP);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.grey[300],
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.black),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _streamingService.dispose();
    _stopAndroidForegroundService();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _startAndroidForegroundService() async {
    if (Platform.isAndroid) {
      const platform = MethodChannel('com.jorin.audio_live_stream/service');
      try {
        await platform.invokeMethod('startAudioStreamingService');
      } on PlatformException catch (e) {
        print("Failed to start foreground service: '${e.message}'.");
      }
    }
  }

  Future<void> _stopAndroidForegroundService() async {
    if (Platform.isAndroid) {
      const platform = MethodChannel('com.jorin.audio_live_stream/service');
      try {
        await platform.invokeMethod('stopAudioStreamingService');
      } on PlatformException catch (e) {
        print("Failed to stop foreground service: '${e.message}'.");
      }
    }
  }
}

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

class CircularWaveformPainter extends CustomPainter {
  final List<int> samples;
  final Color color;
  final double strokeWidth;
  final bool isMicMuted;

  CircularWaveformPainter({
    required this.samples,
    this.color = Colors.blueAccent,
    this.strokeWidth = 2.0,
    required this.isMicMuted,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (isMicMuted || samples.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(center.dx, center.dy);
    final anglePerSample = (2 * pi) / samples.length;

    final path = Path();
    for (int i = 0; i < samples.length; i++) {
      final sample = samples[i];
      final normalizedSample = sample / 32768.0;
      final sampleRadius =
          radius * 0.7 + (radius * 1.0 * normalizedSample.abs());
      final angle = i * anglePerSample;
      final x = center.dx + sampleRadius * cos(angle);
      final y = center.dy + sampleRadius * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
