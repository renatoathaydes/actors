import 'dart:isolate';

class _Message<A> {
  final int id;
  final A content;

  _Message(this.id, this.content);
}

class _BoostrapData {
  final SendPort sendPort;
  final Handler handler;

  _BoostrapData(this.sendPort, this.handler);
}

/// A [Handler] implements the logic an [Actor] should run when receiving
/// a message.
///
/// [Handler]s run in an [Isolate] and hence must not rely on any external
/// state - only the state it maintains internally.
mixin Handler<M, A> {
  /// Handle a message in the [Actor]'s [Isolate], optionally sending
  /// an answer back to the caller.
  A handle(M message);
}

/// An [Actor] is an object which can send messages to a [Handler]
/// running inside a Dart [Isolate].
///
/// It can be seen as the local view of the isolated [Handler], communicating
/// with the other [Isolate] in a transparent manner.
class Actor<M, A> {
  Future<Isolate> isolate;
  ReceivePort _localPort;
  Future<SendPort> _remotePort;
  Stream<_Message> _answerStream;
  int _currentId = -2 ^ 30;

  Actor(Handler<M, A> handler) {
    _localPort = ReceivePort();
    _answerStream = _answers().asBroadcastStream();

    final id = _currentId++;
    _remotePort = _waitForRemotePort(id);
    isolate = Isolate.spawn(
        _remote, _Message(id, _BoostrapData(_localPort.sendPort, handler)));
  }

  Future<SendPort> _waitForRemotePort(int id) async {
    final firstAnswer = await _answerStream.firstWhere((msg) => msg.id == id);
    return firstAnswer.content as SendPort;
  }

  Stream<_Message> _answers() async* {
    await for (var answer in _localPort) {
      yield answer as _Message;
    }
  }

  /// Send a message to the [Handler] this [Actor] is based on.
  ///
  /// The message is handled in another [Isolate] and the handler's
  /// response is sent back asynchronously.
  ///
  /// If an error occurs while the [Handler] handles the message,
  /// the returned [Future] completes with an error,
  /// otherwise it completes with the answer given by the [Handler].
  Future<A> send(M message) async {
    final id = _currentId++;
    final future = _answerStream.firstWhere((msg) => msg.id == id);
    (await _remotePort).send(_Message(id, message));
    final result = await future;
    final content = result.content;
    if (content is Exception) {
      throw content;
    }
    return content as A;
  }
}

Handler _remoteHandler;
SendPort _callerPort;
ReceivePort _remotePort = ReceivePort();

void _remote(msg) async {
  if (_remoteHandler == null) {
    final data = msg.content as _BoostrapData;
    _remoteHandler = data.handler;
    _callerPort = data.sendPort;
    _remotePort.listen(_remote);
    _callerPort.send(_Message(msg.id, _remotePort.sendPort));
  } else {
    assert(msg is _Message);
    var result;
    try {
      result = _remoteHandler.handle(msg.content);
    } catch (e) {
      result = e;
    }
    while (result is Future) {
      result = await result;
    }
    _callerPort.send(_Message(msg.id, result));
  }
}
