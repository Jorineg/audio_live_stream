import 'dart:io';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/services.dart' show rootBundle;

class WebServer {
  HttpServer? _server;
  final List<WebSocketSink> _clients = [];
  Function(int)? onClientCountChanged;
  BonsoirBroadcast? _mdnsBroadcast;

  HttpServer? get server => _server;

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
      (_) {},
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

  void broadcastAudioData(List<int> data) {
    // print('Sende Audiodaten: ${data.length} Bytes an ${_clients.length} Clients');
    List<WebSocketSink> clientsToRemove = [];

    for (var client in _clients) {
      try {
        client.add(data);
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
    } catch (e) {
      print('Fehler beim Stoppen des Servers: $e');
    }
  }

  void dispose() {
    stop();
  }
}
