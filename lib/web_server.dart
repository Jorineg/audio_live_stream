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
  final Set<WebSocketSink> _playingClients = Set();
  Function(int, int)? onClientCountChanged;
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
    onClientCountChanged?.call(_clients.length, _playingClients.length);

    webSocket.stream.listen(
      (message) {
        if (message is String) {
          if (message.startsWith('time:')) {
            _handleTimestampMessage(message);
          } else if (message == 'play') {
            _playingClients.add(webSocket.sink);
            onClientCountChanged?.call(_clients.length, _playingClients.length);
          } else if (message == 'stop') {
            _playingClients.remove(webSocket.sink);
            onClientCountChanged?.call(_clients.length, _playingClients.length);
          }
        }
      },
      onDone: () {
        print('WebSocket-Verbindung geschlossen');
        _clients.remove(webSocket.sink);
        _playingClients.remove(webSocket.sink);
        print('Aktuelle Anzahl der Clients: ${_clients.length}');
        onClientCountChanged?.call(_clients.length, _playingClients.length);
      },
      onError: (error) {
        print('WebSocket-Fehler: $error');
        _clients.remove(webSocket.sink);
        _playingClients.remove(webSocket.sink);
        print('Aktuelle Anzahl der Clients: ${_clients.length}');
        onClientCountChanged?.call(_clients.length, _playingClients.length);
      },
    );
  }

  int get connectedClients => _clients.length;

  String lastMicStatus = 'mic_muted';

  void broadcastAudioData(Uint8List data) {
    List<WebSocketSink> clientsToRemove = [];

    for (var client in _playingClients) {
      try {
        client.add(data);
      } catch (e) {
        print('Fehler beim Senden an Client: $e');
        clientsToRemove.add(client);
      }
    }

    if (clientsToRemove.isNotEmpty) {
      _clients.removeWhere((client) => clientsToRemove.contains(client));
      _playingClients.removeWhere((client) => clientsToRemove.contains(client));
      onClientCountChanged?.call(_clients.length, _playingClients.length);
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
    final String serviceName = '$mdnsName.local';
    _mdnsBroadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: serviceName,
        type: '_http._tcp',
        port: port,
      ),
    );
    await _mdnsBroadcast!.ready;
    await _mdnsBroadcast!.start();
    print('mDNS-Service mit Namen $serviceName auf Port $port registriert');
  }

  Future<void> stop() async {
    try {
      await _server?.close();
      for (var client in _clients) {
        await client.close();
      }
      _clients.clear();
      print('Server gestoppt');
      // Change mDNS cleanup
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
