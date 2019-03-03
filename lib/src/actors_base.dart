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

/// A [Handler] implements the logic to handle messages.
mixin Handler<M, A> {
  /// Handle a message, optionally sending an answer back to the caller.
  A handle(M message);
}

/// A [Messenger] can send a message and receive an answer asynchronously.
mixin Messenger<M, A> {
  /// Send a message and get a [Future] to receive the answer at some later
  /// point in time, asynchronously.
  Future<A> send(M message);
}

/// An [Actor] is an entity that can send messages to a [Handler]
/// running inside a Dart [Isolate].
///
/// It can be seen as the local view of the isolated [Handler] that handles
/// messages sent via the [Actor], communicating
/// with the associated [Isolate] in a transparent manner.
///
/// Because [Actor]s are mapped 1-1 to [Isolate]s, they are not cheap to create
/// and the same limitations of [Isolate]s also apply to [Actor]s:
///
/// * messages sent to [Actor]s must be copied into the [Isolate] the [Actor]
///   is running on.
/// * the number of processing intensive [Actor]s should be around that
///   of the number of CPUs available.
/// * it may make sense to have a larger amount of [Actor]s if they are mostly
///   IO-bound.
class Actor<M, A> with Messenger<M, A> {
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
  @override
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
