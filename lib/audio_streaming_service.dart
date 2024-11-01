import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'web_server.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class AudioStreamingService {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final WebServer webServer = WebServer();
  bool _isRecording = false;
  bool _isInitialized = false;
  StreamController<double> _micLevelController = StreamController.broadcast();
  StreamController<Uint8List> _audioSampleController =
      StreamController.broadcast();
  Stream<Uint8List> get audioSampleStream => _audioSampleController.stream;
  int _bitRate = 64 * 1000;
  final int _sampleRate = 16000;
  final int _bufferSize = 1024 * 2;
  final int _numChannels = 1; // Mono

  Stream<double> get micLevelStream => _micLevelController.stream;

  Future<void> initialize() async {
    if (!_isInitialized) {
      await Permission.microphone.request();
      await _recorder.openRecorder();
      await _recorder.setSubscriptionDuration(const Duration(milliseconds: 10));
      _isInitialized = true;
    }
  }

  Future<void> startServer(String mdnsName) async {
    await webServer.start(mdnsName);
  }

  Future<void> stopServer() async {
    await webServer.stop();
  }

  Future<void> startStreaming() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (!_isRecording) {
      if (await Permission.microphone.isGranted) {
        try {
          WakelockPlus.enable(); // Enable wakelock
          await _resetRecorder();
          // StreamController<Food> recordingDataController =
          //     StreamController<Food>();
          // recordingDataController.stream.listen((food) {
          //   if (food is FoodData && food.data != null) {
          //     webServer.broadcastAudioData(food.data!);
          //   }
          // });
          StreamController<Uint8List> recordingDataController =
              StreamController<Uint8List>();
          recordingDataController.stream.listen((data) {
            _audioSampleController.add(Uint8List.fromList(data));
            // _audioSampleController.add(data);
            // take two bytes and rescale to one byte
            // Uint8List scaledData = Uint8List(data.length ~/ 2);
            // for (int i = 0; i < scaledData.length; i++) {
            //   scaledData[i] = data[i * 2 + 1];
            // }
            // webServer.broadcastAudioData(scaledData);
            webServer.broadcastAudioData(data);
          });

          await _recorder.startRecorder(
            toStream: recordingDataController,
            codec: Codec.pcm16, // Changed to PCM 16-bit
            numChannels: _numChannels,
            sampleRate: _sampleRate,
            bufferSize: _bufferSize,
          );

          print(
              "start streaming with bitrate: $_bitRate, sampleRate: $_sampleRate, bufferSize: $_bufferSize");

          _recorder.onProgress?.listen((RecordingDisposition disposition) {
            final level = disposition.decibels ?? 0.0;
            if (level > 0) {
              _micLevelController.add(level);
            }
          });
          _isRecording = true;
          print('Recording started successfully');
          webServer.broadcastStatusMessage('mic_active');
          webServer.lastMicStatus = 'mic_active';
        } catch (e) {
          print('Error starting recording: $e');
          await _resetRecorder();
          WakelockPlus.disable(); // Disable wakelock if there's an error
        }
      } else {
        print('Microphone permission not granted');
      }
    }
  }

  Future<void> stopStreaming() async {
    if (_isRecording) {
      try {
        await _recorder.stopRecorder();
        _isRecording = false;
        print('Recording stopped successfully');
        webServer.broadcastStatusMessage('mic_muted');
        webServer.lastMicStatus = 'mic_muted';
        WakelockPlus.disable(); // Disable wakelock when stopping
      } catch (e) {
        print('Error stopping recording: $e');
        await _resetRecorder();
        _isRecording = false;
      }
    }
  }

  Future<void> _resetRecorder() async {
    try {
      await _recorder.closeRecorder();
      await _recorder.openRecorder();
      await _recorder.setSubscriptionDuration(const Duration(milliseconds: 5));
    } catch (e) {
      print('Fehler beim Zurücksetzen des Recorders: $e');
    }
  }

  Future<void> dispose() async {
    await stopStreaming();
    await _recorder.closeRecorder();
    await webServer.stop();
    _micLevelController.close();
    _isInitialized = false;
  }

  void setBitrate(int kbps) {
    _bitRate = kbps * 1000;
  }
}

class CustomStreamSink implements StreamSink<Uint8List> {
  final Function(List<int>) _onData;

  CustomStreamSink(this._onData);

  @override
  void add(Uint8List data) {
    // Debug-Log
    // print('Empfangene Audiodaten: ${data.length} Bytes');
    _onData(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream<Uint8List> stream) async {
    await for (var data in stream) {
      add(data);
    }
  }

  @override
  Future close() async {}

  @override
  Future get done => Future.value();
}
