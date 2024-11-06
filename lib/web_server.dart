import 'dart:io';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:async';

class WebServer {
  HttpServer? _server;
  final List<WebSocketSink> _clients = [];
  Function(int)? onClientCountChanged;
  BonsoirBroadcast? _mdnsBroadcast;
  final StreamController<double> _latencyStreamController =
      StreamController.broadcast();
  double _emaLatency = 0.0;

  HttpServer? get server => _server;
  Stream<double> get latencyStream => _latencyStreamController.stream;

  Future<void> start(String mdnsName) async {
    if (_server != null) {
      print('Server läuft bereits auf Port ${_server!.port}');
      return;
    }

    List<int> portsToTry = [8080, 80];
    bool serverStarted = false;
    for (var port in portsToTry) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        serverStarted = true;
        print('WebSocket-Server gestartet auf Port ${_server!.port}');
        _server!.listen((HttpRequest request) {
          if (WebSocketTransformer.isUpgradeRequest(request)) {
            WebSocketTransformer.upgrade(request).then((WebSocket socket) {
              _handleWebSocket(IOWebSocketChannel(socket));
            });
          } else {
            _handleHttpRequest(request);
          }
        });
        break;
      } catch (e) {
        print('Fehler beim Starten des Servers auf Port $port: $e');
      }
    }

    if (!serverStarted) {
      // Wenn bevorzugte Ports nicht verfügbar, beliebigen Port verwenden
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
        serverStarted = true;
        print('WebSocket-Server gestartet auf Port ${_server!.port}');
        _server!.listen((HttpRequest request) {
          if (WebSocketTransformer.isUpgradeRequest(request)) {
            WebSocketTransformer.upgrade(request).then((WebSocket socket) {
              _handleWebSocket(IOWebSocketChannel(socket));
            });
          } else {
            _handleHttpRequest(request);
          }
        });
      } catch (e) {
        print('Fehler beim Starten des Servers auf zufälligem Port: $e');
        throw Exception('Server konnte auf keinem Port gestartet werden');
      }
    }

    // mDNS-Service registrieren
    await _registerMDNSService(mdnsName);

    // Start sending timestamp messages to clients
    _sendTimestampMessages();
  }

  void _handleHttpRequest(HttpRequest request) async {
    String path = request.uri.path;

    if (path == '/') {
      path = '/index.html';
    }

    String assetPath = 'assets/www$path';
    try {
      if (path.endsWith('.html') ||
          path.endsWith('.js') ||
          path.endsWith('.css')) {
        final data = await rootBundle.loadString(assetPath);
        String contentType = 'text/plain';
        if (path.endsWith('.html')) {
          contentType = 'text/html';
        } else if (path.endsWith('.js')) {
          contentType = 'application/javascript';
        } else if (path.endsWith('.css')) {
          contentType = 'text/css';
        }
        request.response.headers.contentType = ContentType.parse(contentType);
        request.response.write(data);
      } else {
        final ByteData bytes = await rootBundle.load(assetPath);
        List<int> buffer = bytes.buffer.asUint8List();
        String contentType = 'application/octet-stream';
        if (path.endsWith('.png')) {
          contentType = 'image/png';
        } else if (path.endsWith('.svg')) {
          contentType = 'image/svg+xml';
        }
        request.response.headers.contentType = ContentType.parse(contentType);
        request.response.add(buffer);
      }
    } catch (e) {
      print('Error loading asset: $e');
      print('Requested asset path: $assetPath');
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('404 Not Found: $path');
    }
    await request.response.close();
  }

  void _handleWebSocket(WebSocketChannel webSocket) {
    print('Neue WebSocket-Verbindung hergestellt');
    webSocket.sink.add(lastMicStatus);
    _clients.add(webSocket.sink);
    print('Aktuelle Anzahl der Clients: ${_clients.length}');
    onClientCountChanged?.call(_clients.length);

    webSocket.stream.listen(
      (message) {
        if (message is String && message.startsWith('time:')) {
          _handleTimestampMessage(message);
        }
      },
      onDone: () {
        print('WebSocket-Verbindung geschlossen');
        _clients.remove(webSocket.sink);
        print('Aktuelle Anzahl der Clients: ${_clients.length}');
        onClientCountChanged?.call(_clients.length);
      },
      onError: (error) {
        print('WebSocket-Fehler: $error');
        _clients.remove(webSocket.sink);
        print('Aktuelle Anzahl der Clients: ${_clients.length}');
        onClientCountChanged?.call(_clients.length);
      },
    );
  }

  int get connectedClients => _clients.length;

  String lastMicStatus = 'mic_muted';

  Uint8List encodeADPCM8Bit(Uint8List input) {
    int len = input.length ~/ 2; // Number of 16-bit samples
    Uint8List output =
        Uint8List((len + 1) ~/ 2); // Each byte will hold two 4-bit codes

    // ADPCM encoder variables
    int prevSample = 0;
    int index = 0;

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

    return output;
  }

  void broadcastAudioData(Uint8List data) {
    // print('Sende Audiodaten: ${data.length} Bytes an ${_clients.length} Clients');
    List<WebSocketSink> clientsToRemove = [];

    Uint8List adpcmData = encodeADPCM8Bit(data);
    //print first 5 bytes of original and adpcm data
    // print('Original data: ${data.sublist(0, 5)}, ADPCM data: ${adpcmData.sublist(0, 5)}');

    for (var client in _clients) {
      try {
        client.add(adpcmData);
      } catch (e) {
        print('Fehler beim Senden an Client: $e');
        clientsToRemove.add(client);
      }
    }

    if (clientsToRemove.isNotEmpty) {
      _clients.removeWhere((client) => clientsToRemove.contains(client));
      onClientCountChanged?.call(_clients.length);
    }
  }

  void broadcastStatusMessage(String message) {
    for (var client in _clients) {
      try {
        client.add(message);
      } catch (e) {
        print('Fehler beim Senden an Client: $e');
      }
    }
  }

  Future<void> _registerMDNSService(String mdnsName) async {
    final int port = _server!.port;
    _mdnsBroadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: mdnsName,
        type: '_http._tcp',
        port: port,
      ),
    );
    await _mdnsBroadcast!.ready;
    await _mdnsBroadcast!.start();
    print('mDNS-Service mit Namen $mdnsName auf Port $port registriert');
  }

  Future<void> stop() async {
    try {
      await _server?.close();
      for (var client in _clients) {
        await client.close();
      }
      _clients.clear();
      print('Server gestoppt');
      // mDNS-Service stoppen
      await _mdnsBroadcast?.stop();
      _mdnsBroadcast = null;
      _latencyStreamController.close();
    } catch (e) {
      print('Fehler beim Stoppen des Servers: $e');
    }
  }

  void dispose() {
    stop();
  }

  void _sendTimestampMessages() {
    Timer.periodic(Duration(seconds: 1), (timer) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final message = 'time:$timestamp';
      for (var client in _clients) {
        try {
          client.add(message);
        } catch (e) {
          print('Fehler beim Senden der Zeitstempel-Nachricht: $e');
        }
      }
    });
  }

  void _handleTimestampMessage(String message) {
    final sentTimestamp = int.tryParse(message.split(':')[1]);
    if (sentTimestamp != null) {
      final receivedTimestamp = DateTime.now().millisecondsSinceEpoch;
      final roundTripTime = receivedTimestamp - sentTimestamp;
      final averageLatency = roundTripTime / 2;
      _emaLatency = _calculateEMA(_emaLatency, averageLatency.toDouble());
      _latencyStreamController.add(_emaLatency);
    }
  }

  double _calculateEMA(double previousEMA, double newValue) {
    const double alpha = 0.2;
    return alpha * newValue + (1 - alpha) * previousEMA;
  }
}
