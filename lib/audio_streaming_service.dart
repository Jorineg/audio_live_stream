import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'web_server.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:convert';
import 'dart:math';

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
  final int _sampleRate =
      22000; // Ensure the microphone always records at 22k sample rate
  final int _bufferSize = 1024 * 2;
  final int _numChannels = 1; // Mono
  double _currentSampleRate = 16000; // Default sample rate
  bool _adpcmCompression = false; // Default ADPCM compression state

  int prevSample = 0;
  int index = 0;

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

  // first bit of the header byte is used to indicate ADPCM compression: 0 = false, 1 = true
  // other bits indicate sample rate in kHz: 0010110 = 22 kHz (decimal 22), etc.
  int getHeaderByte() {
    int header = 0;
    if (_adpcmCompression) {
      header |= 0x80; // Set the first bit to 1
    }
    int sampleRate = _currentSampleRate ~/ 1000;
    header |= sampleRate;
    return header & 0xFF;
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
            Uint8List downsampledData =
                _downsample(data, _sampleRate, _currentSampleRate);
            if (_adpcmCompression) {
              downsampledData = _encodeADPCM8Bit(downsampledData);
            }
            Uint8List dataWithHeader = Uint8List(downsampledData.length + 1);
            dataWithHeader[0] = getHeaderByte();
            dataWithHeader.setRange(1, dataWithHeader.length, downsampledData);
            webServer.broadcastAudioData(dataWithHeader);
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

  void setSampleRate(double sampleRate) {
    _currentSampleRate = sampleRate;
  }

  void setAdpcmCompression(bool adpcmCompression) {
    _adpcmCompression = adpcmCompression;
  }

  Uint8List _downsample(
      Uint8List input, int inputSampleRate, double outputSampleRate) {
    if (inputSampleRate == outputSampleRate) {
      return input;
    }

    // Convert Uint8List to List<double> (assuming 16-bit PCM)
    final int numSamples = input.length ~/ 2;
    final samples = List<double>.generate(numSamples, (i) {
      int index = i * 2;
      // Little-endian to int16
      int sample = input[index] | (input[index + 1] << 8);
      // Convert to signed value
      if (sample >= 0x8000) sample -= 0x10000;
      return sample.toDouble();
    });

    // Apply low-pass filter
    final filteredSamples =
        _lowPassFilter(samples, inputSampleRate, outputSampleRate);

    // Resample
    final sampleRateRatio = outputSampleRate / inputSampleRate;
    final newLength = (filteredSamples.length * sampleRateRatio).round();
    final resampledSamples = List<double>.generate(newLength, (i) {
      final index = i / sampleRateRatio;
      final floorIndex = index.floor();
      final ceilIndex = index.ceil();
      if (ceilIndex >= filteredSamples.length) {
        return filteredSamples.last;
      }
      final weight = index - floorIndex;
      return filteredSamples[floorIndex] * (1 - weight) +
          filteredSamples[ceilIndex] * weight;
    });

    // Convert back to Uint8List
    final output = Uint8List(newLength * 2);
    for (int i = 0; i < newLength; i++) {
      int sample = resampledSamples[i].round();
      // Clipping
      if (sample > 32767) sample = 32767;
      if (sample < -32768) sample = -32768;
      // Convert to little-endian bytes
      output[i * 2] = sample & 0xFF;
      output[i * 2 + 1] = (sample >> 8) & 0xFF;
    }

    return output;
  }

  List<double> _lowPassFilter(
      List<double> samples, int inputSampleRate, double outputSampleRate) {
    final cutoffFreq = outputSampleRate / 2; // Nyquist frequency
    final filterLength = 101; // Adjust for your needs (must be odd)
    final filter = List<double>.filled(filterLength, 0);
    final m = (filterLength - 1) / 2;

    // Sinc filter coefficients
    for (int n = 0; n < filterLength; n++) {
      if (n == m) {
        filter[n] = 2 * cutoffFreq / inputSampleRate;
      } else {
        final piTerm = pi * (n - m);
        filter[n] =
            sin(2 * cutoffFreq * (n - m) * pi / inputSampleRate) / piTerm;
      }
      // Apply Hamming window
      filter[n] *= 0.54 - 0.46 * cos(2 * pi * n / (filterLength - 1));
    }

    // Normalize filter coefficients
    final sum = filter.reduce((a, b) => a + b);
    for (int n = 0; n < filterLength; n++) {
      filter[n] /= sum;
    }

    // Convolve signal with filter
    final paddedSamples =
        List<double>.filled(samples.length + filterLength - 1, 0);
    for (int i = 0; i < samples.length; i++) {
      paddedSamples[i + (filterLength ~/ 2)] = samples[i];
    }

    final output = List<double>.filled(samples.length, 0);
    for (int i = 0; i < samples.length; i++) {
      double acc = 0;
      for (int j = 0; j < filterLength; j++) {
        acc += paddedSamples[i + j] * filter[j];
      }
      output[i] = acc;
    }

    return output;
  }

  Uint8List _encodeADPCM8Bit(Uint8List input) {
    int len = input.length ~/ 2; // Number of 16-bit samples
    Uint8List output =
        Uint8List((len + 1) ~/ 2); // Each byte holds two 4-bit codes

    // Step size table (standard IMA ADPCM table with 89 entries)
    List<int> stepSizeTable = [
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      16,
      17,
      19,
      21,
      23,
      25,
      28,
      31,
      34,
      37,
      41,
      45,
      50,
      55,
      60,
      66,
      73,
      80,
      88,
      97,
      107,
      118,
      130,
      143,
      157,
      173,
      190,
      209,
      230,
      253,
      279,
      307,
      337,
      371,
      408,
      449,
      494,
      544,
      598,
      658,
      724,
      796,
      876,
      963,
      1060,
      1166,
      1282,
      1411,
      1552,
      1707,
      1878,
      2066,
      2272,
      2499,
      2749,
      3024,
      3327,
      3660,
      4026,
      4428,
      4871,
      5358,
      5894,
      6484,
      7132,
      7845,
      8630,
      9493,
      10442,
      11487,
      12635,
      13899,
      15289,
      16818,
      18500,
      20350,
      22385,
      24623,
      27086,
      29794,
      32767
    ];

    // Index table for ADPCM
    List<int> indexTable = [-1, -1, -1, -1, 2, 4, 6, 8];

    // Prepare header with prevSample and index
    ByteData header = ByteData(4);
    header.setInt16(0, prevSample, Endian.little); // 2 bytes for prevSample
    header.setUint8(2, index); // 1 byte for index
    header.setUint8(3, 0); // 1 blank byte for even byte count

    for (int n = 0; n < len; n++) {
      int sample = (input[n * 2] & 0xFF) | ((input[n * 2 + 1] & 0xFF) << 8);
      if (sample > 32767) sample -= 65536; // Convert to signed 16-bit

      int diff = sample - prevSample;
      int sign = (diff < 0) ? 8 : 0;
      if (sign != 0) diff = -diff;

      int step = stepSizeTable[index];
      int diffq = 0;

      int code = 0;
      if (diff >= step) {
        code |= 4;
        diff -= step;
        diffq += step;
      }
      step >>= 1;
      if (diff >= step) {
        code |= 2;
        diff -= step;
        diffq += step;
      }
      step >>= 1;
      if (diff >= step) {
        code |= 1;
        diffq += step;
      }

      code |= sign;

      // Update previous sample estimate
      diffq += stepSizeTable[index] >> 3;
      if (sign != 0)
        prevSample -= diffq;
      else
        prevSample += diffq;

      // Clamp prevSample to 16-bit
      if (prevSample > 32767)
        prevSample = 32767;
      else if (prevSample < -32768) prevSample = -32768;

      // Update index
      index += indexTable[code & 0x07];
      if (index < 0)
        index = 0;
      else if (index > 88) index = 88;

      // Pack two 4-bit codes into one byte
      if (n % 2 == 0) {
        // Store in higher nibble
        output[n ~/ 2] = (code & 0x0F) << 4;
      } else {
        // Store in lower nibble
        output[n ~/ 2] |= (code & 0x0F);
      }
    }

    // Combine header and output data
    Uint8List packet = Uint8List(header.lengthInBytes + output.length);
    packet.setRange(0, header.lengthInBytes, header.buffer.asUint8List());
    packet.setRange(header.lengthInBytes, packet.length, output);

    return packet;
  }

  double getCurrentDataSendRate() {
    int bitsPerSample = _adpcmCompression ? 4 : 16;
    double dataRatePerClient =
        (_currentSampleRate * bitsPerSample) / 1000; // in kbps
    return dataRatePerClient;
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
