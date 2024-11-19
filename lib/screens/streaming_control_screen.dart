import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:typed_data';

import '../audio_streaming_service.dart';
import '../utils/network_utils.dart';
import '../utils/platform_utils.dart';
import '../widgets/bitrate_slider.dart';
import '../widgets/circular_waveform_painter.dart';
import 'qr_code_screen.dart';
import 'introduction_screen.dart';
import 'package:permission_handler/permission_handler.dart';

class StreamingControl extends StatefulWidget {
  const StreamingControl({super.key});

  @override
  _StreamingControlState createState() => _StreamingControlState();
}

class _StreamingControlState extends State<StreamingControl> {
  final AudioStreamingService _streamingService = AudioStreamingService();
  bool _isStreaming = false;
  String _ipAddress = 'Loading...';
  String _hostname = 'Loading...';
  String _serverAddressIP = '';
  int _connectedClients = 0;
  String _mdnsName = 'audiostream';
  String? _errorMessage;
  bool _serverStarting = true;
  List<int> _audioSamples = [];
  double _latency = 0.0;
  double _emaLatency = 0.0;
  Timer? _timer;

  double _sampleRate = 16000;
  bool _adpcmCompression = false;

  Timer? _ipCheckTimer;
  List<String> _currentIpAddresses = [];
  bool _initialIpCheck = true;
  bool _isDialogVisible = false;

  static const platform =
      MethodChannel('com.jorin.audio_live_stream/app_control');

  int _playingClients = 0;

  @override
  void initState() {
    super.initState();
    _initializeStreaming();
    _initializeNetworking();
    _initializeAudioProcessing();
  }

  void _initializeNetworking() async {
    await _getIpAddress();
    await PlatformUtils.getDeviceName().then((name) {
      setState(() {
        _hostname = name;
        _mdnsName = _processMDNSName(name);
      });
    });
    _startIpAddressMonitoring();
  }

  void _initializeAudioProcessing() {
    _streamingService.audioSampleStream.listen((data) {
      setState(() {
        _audioSamples = _processAudioSamples(data);
      });
    });

    _streamingService.webServer.onClientCountChanged = (count, playingCount) {
      setState(() {
        _connectedClients = count;
        _playingClients = playingCount;
      });
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

  // Server Management Methods
  Future<void> _initializeStreaming() async {
    try {
      await _streamingService.initialize();
    } catch (e) {
      if (e == 'microphone_permission_required') {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Microphone Permission Required'),
              content: const Text(
                'For audio streaming to work, please give permission to use the microphone.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await Permission.microphone.request();
                    // Try to initialize again after permission request
                    await _streamingService.initialize();
                  },
                  child: const Text('Allow'),
                ),
              ],
            );
          },
        );
      }
    }
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
        _serverStarting = false;
      });
    } catch (e) {
      print('Error starting server: $e');
      if (mounted) {
        setState(() {
          _serverStarting = false;
          _errorMessage = 'Error starting server: $e';
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
    });
  }

  // Audio Control Methods
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
    });
  }

  void _startStreaming() {
    if (_serverStarting) {
      showMessage('Please wait, the server is still starting');
      return;
    }
    setState(() {
      _isStreaming = true;
    });
    PlatformUtils.startAndroidForegroundService();
    _streamingService.startStreaming();
  }

  void _stopStreaming() {
    _streamingService.stopStreaming();
    PlatformUtils.stopAndroidForegroundService();
    setState(() {
      _isStreaming = false;
    });
  }

  // Network Methods
  Future<void> _getIpAddress() async {
    List<String> ipAddresses = await NetworkUtils.getLocalIpAddresses();
    setState(() {
      _ipAddress = ipAddresses.isNotEmpty ? ipAddresses.first : 'Unknown';
      _currentIpAddresses = ipAddresses;
    });
  }

  void _startIpAddressMonitoring() {
    _ipCheckTimer = Timer.periodic(Duration(seconds: 1), (timer) async {
      List<String> newIpAddresses = await NetworkUtils.getLocalIpAddresses();

      if (_initialIpCheck) {
        _initialIpCheck = false;
        if (newIpAddresses.isEmpty) {
          _showNetworkDialog('No network detected',
              'Please connect to a wifi network or activate a wifi hotspot and restart the app');
        }
        return;
      }

      _handleNetworkChanges(newIpAddresses);
    });
  }

  void _handleNetworkChanges(List<String> newIpAddresses) {
    bool hasRemovedIps =
        _currentIpAddresses.any((ip) => !newIpAddresses.contains(ip));
    bool hasNewIps =
        newIpAddresses.any((ip) => !_currentIpAddresses.contains(ip));

    if (_currentIpAddresses.length != newIpAddresses.length ||
        hasRemovedIps ||
        hasNewIps) {
      _showNetworkDialog('Network Change Detected',
          'Please connect to a wifi network or activate a wifi hotspot and restart the app');
    }

    setState(() {
      _currentIpAddresses = newIpAddresses;
      _ipAddress = newIpAddresses.isNotEmpty ? newIpAddresses.first : 'Unknown';
    });
  }

  // Utility Methods
  List<int> _processAudioSamples(Uint8List data) {
    final audioData = ByteData.sublistView(data);
    List<int> samples = [];
    for (int i = 0; i < audioData.lengthInBytes; i += 2) {
      samples.add(audioData.getInt16(i, Endian.little));
    }

    int desiredSampleCount = 360;
    int step = samples.length ~/ desiredSampleCount;
    if (step < 1) step = 1;

    return [for (int i = 0; i < samples.length; i += step) samples[i]];
  }

  String _processMDNSName(String name) {
    return name.toLowerCase().replaceAll(RegExp(r'\s+'), '-');
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

  void _showNetworkDialog(String title, String content) {
    if (_isDialogVisible) return;

    setState(() => _isDialogVisible = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            child: Text('Cancel'),
            onPressed: () {
              setState(() => _isDialogVisible = false);
              Navigator.of(context).pop();
            },
          ),
          TextButton(
            child: Text('Restart App'),
            onPressed: () async {
              await _stopServer(); // Clean up resources
              try {
                if (Platform.isAndroid) {
                  await platform.invokeMethod('restartApp');
                } else {
                  exit(0); // Fallback for iOS
                }
              } catch (e) {
                print('Error restarting app: $e');
                // Fallback to regular exit
                if (Platform.isAndroid) {
                  SystemNavigator.pop();
                } else {
                  exit(0);
                }
              }
            },
          ),
        ],
      ),
    ).then((_) => setState(() => _isDialogVisible = false));
  }

  // Build Method
  @override
  Widget build(BuildContext context) {
    double dataSendRate =
        _streamingService.getCurrentDataSendRate() * _playingClients;
    String dataSendRateText = dataSendRate >= 1000
        ? '${(dataSendRate / 1000).toStringAsFixed(2)} Mbps'
        : '${dataSendRate.toStringAsFixed(0)} kbps';
    Color dataSendRateColor = dataSendRate > 10000 ? Colors.red : Colors.grey;

    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi Audio Stream'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const IntroductionScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Connected: $_connectedClients    Playing: $_playingClients',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            Center(
              child: GestureDetector(
                onTap: _toggleStreaming,
                child: _buildMicrophoneControl(),
              ),
            ),
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
            _buildStatusSection(dataSendRateText, dataSendRateColor),
            _buildAudioControls(),
            _buildConnectionCard(),
            if (_errorMessage != null) _buildErrorMessage(),
          ],
        ),
      ),
    );
  }

  Widget _buildMicrophoneControl() {
    return Stack(
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
            double micLevel = (snapshot.data ?? 0.0) / 100;
            Color iconColor = _serverStarting
                ? Colors.grey
                : _isStreaming
                    ? HSLColor.fromAHSL(1, (130 - micLevel * 170).clamp(0, 360),
                            (micLevel * 40 + 60).clamp(60, 100) / 100, 0.5)
                        .toColor()
                    : Colors.grey;
            IconData iconData = _isStreaming ? Icons.mic : Icons.mic_off;
            return Icon(iconData, size: 100.0, color: iconColor);
          },
        ),
      ],
    );
  }

  Widget _buildStatusSection(String dataSendRateText, Color dataSendRateColor) {
    return Column(
      children: [
        Text(
          _connectedClients == 0 || _latency > 2000
              ? 'Latency: -'
              : 'Latency: ${_latency.toStringAsFixed(0).padLeft(4, ' ')} ms',
          textAlign: TextAlign.center,
          style: TextStyle(color: _latency > 500 ? Colors.red : Colors.grey),
        ),
        Text(
          'Send Rate: $dataSendRateText',
          textAlign: TextAlign.center,
          style: TextStyle(color: dataSendRateColor),
        ),
      ],
    );
  }

  Widget _buildAudioControls() {
    return Column(
      children: [
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
                      setState(() {
                        _adpcmCompression = value;
                        _streamingService.setAdpcmCompression(value);
                      });
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
          min: 10000,
          max: 22000,
          divisions: 12,
          label: '${_sampleRate.toInt()} Hz',
          onChanged: (double value) {
            setState(() {
              _sampleRate = value;
              _streamingService.setSampleRate(value);
            });
          },
        ),
      ],
    );
  }

  Widget _buildConnectionCard() {
    if (_serverStarting) {
      return const Center(
        child: Text('Server is starting...', textAlign: TextAlign.center),
      );
    }

    return Card(
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) =>
                  QRCodeScreen(serverAddress: _serverAddressIP),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(
                'Tap to Connect',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                _serverAddressIP,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.grey[300],
      child: Text(
        _errorMessage!,
        style: const TextStyle(color: Colors.black),
        textAlign: TextAlign.center,
      ),
    );
  }

  @override
  void dispose() {
    _streamingService.dispose();
    PlatformUtils.stopAndroidForegroundService();
    _timer?.cancel();
    _ipCheckTimer?.cancel();
    super.dispose();
  }
}
