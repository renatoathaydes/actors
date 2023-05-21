import 'dart:async';
import 'dart:io';

import 'package:actors/actors.dart';
import 'package:test/expect.dart';
import 'package:test/scaffolding.dart';

/// This [Handler] starts a HTTP Server that can be used for testing that a
/// HTTP client is sending HTTP headers correctly.
/// It initializes the server on the [init] method to avoid errors related
/// to trying to _send_ the HttpServer in the actor initial message.
class HttpServerActor with Handler<void, HttpHeaders?> {
  late final HttpServer _server;
  final int port;

  // keep a list with the received HTTP request headers to be able to send them
  // back to the client on request.
  final List<HttpHeaders> _receivedHeaders = [];

  // notice that only "sendable" state can be initialized or provided
  // in the constructor.
  HttpServerActor(this.port);

  // this method will only run in the Actor's own Isolate, so we can
  // create non-sendable state.
  @override
  Future<void> init() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    unawaited(_serveRequests());
  }

  @override
  HttpHeaders? handle(void _) {
    return _receivedHeaders.firstOrNull;
  }

  @override
  Future<void> close() async {
    await _server.close();
  }

  Future<void> _serveRequests() async {
    await for (final req in _server) {
      _receivedHeaders.add(req.headers);
      await req.response.close();
    }
  }
}

/// This test is executed as part of this package's standard tests.
void main() {
  Actor<void, HttpHeaders?>? httpActor;

  tearDown(() => httpActor?.close());

  test('can start an actor which maintains non-sendable state', () async {
    final port = 8081;
    httpActor = Actor(HttpServerActor(port));

    // send a request with some header
    final client = HttpClient();
    final req = await client.get('localhost', port, '/');
    req.headers.add('Custom-Header', 'Foo');
    final res = await req.close();

    expect(res.statusCode, equals(200));

    // make sure the actor can send back the headers we've sent
    final receivedHeaders = await httpActor!.send(null);

    expect(receivedHeaders, isNotNull);
    expect(receivedHeaders!['Custom-Header'], equals(['Foo']));
  });
}
