import 'dart:async';
import 'dart:isolate';

class _Message<A> {
  final int id;
  final A content;

  _Message(this.id, this.content);
}

class _BoostrapData<M, A> {
  final SendPort sendPort;
  final Handler<M, A> handler;

  _BoostrapData(this.sendPort, this.handler);
}

typedef HandlerFunction<M, A> = FutureOr<A> Function(M message);

/// A [Handler] implements the logic to handle messages.
mixin Handler<M, A> {
  /// Handle a message, optionally sending an answer back to the caller.
  FutureOr<A> handle(M message);
}

class _HandlerOfFunction<M, A> with Handler<M, A> {
  final HandlerFunction<M, A> _function;

  _HandlerOfFunction(this._function);

  @override
  FutureOr<A> handle(M message) => _function(message);
}

/// Wrap a [HandlerFunction] into a [Handler] object.
Handler<M, A> asHandler<M, A>(HandlerFunction<M, A> handlerFunction) =>
    _HandlerOfFunction(handlerFunction);

/// A [Messenger] can send a message and receive an answer asynchronously.
mixin Messenger<M, A> {
  /// Send a message and get a [Future] to receive the answer at some later
  /// point in time, asynchronously.
  FutureOr<A> send(M message);

  /// Close this [Messenger].
  FutureOr close();
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

  /// Creates an [Actor] that handles messages with the given [Handler].
  ///
  /// Use the [of] constructor to wrap a function directly.
  Actor(Handler<M, A> handler) {
    if (A.toString().startsWith('Stream<')) {
      throw StateError(
          "Actor cannot return a Stream. Use StreamActor instead.");
    }
    _localPort = ReceivePort();
    _answerStream = _answers().asBroadcastStream();

    final id = _currentId++;
    _remotePort = _waitForRemotePort(id);
    isolate = Isolate.spawn(
        _remote, _Message(id, _BoostrapData(_localPort.sendPort, handler)));
  }

  /// Creates an [Actor] based on a handler function.
  Actor.of(HandlerFunction<M, A> handler) : this(asHandler(handler));

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
  FutureOr<A> send(M message) async {
    final id = _currentId++;
    final future = _answerStream.firstWhere((answer) => answer.id == id);
    (await _remotePort).send(_Message(id, message));
    final result = await future;
    final Object content = result.content;
    if (content is Exception) {
      throw content;
    }
    return content as FutureOr<A>;
  }

  FutureOr close() async {
    (await isolate).kill(priority: Isolate.immediate);
  }
}

class StreamActor<M, A> with Messenger<M, Stream<A>> {
  Future<Isolate> isolate;
  ReceivePort _localPort;
  Future<SendPort> _remotePort;
  Stream<_Message> _answerStream;
  int _currentId = -2 ^ 30;

  /// Creates an [Actor] that handles messages with the given [Handler].
  ///
  /// Use the [of] constructor to wrap a function directly.
  StreamActor(Handler<M, Stream<A>> handler) {
    _localPort = ReceivePort();
    _answerStream = _answers().asBroadcastStream();

    final id = _currentId++;
    _remotePort = _waitForRemotePort(id);
    isolate = Isolate.spawn(
        _remote, _Message(id, _BoostrapData(_localPort.sendPort, handler)));
  }

  /// Creates an [Actor] based on a handler function.
  StreamActor.of(HandlerFunction<M, Stream<A>> handler)
      : this(asHandler(handler));

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
  FutureOr<Stream<A>> send(M message) async {
    final id = _currentId++;
    (await _remotePort).send(_Message(id, message));
    return _answerStream
        .where((answer) => answer.id == id)
        .takeWhile((item) => item.content != #actors_stream_done)
        .map((answer) => answer.content as A);
  }

  FutureOr close() async {
    (await isolate).kill(priority: Isolate.immediate);
  }
}

/////////////////////////////////////////////////////////
// Below this line, we define the remote Actor behaviour,
// i.e. the code that runs in the Actor's Isolate.
/////////////////////////////////////////////////////////

Handler _remoteHandler;
SendPort _callerPort;
ReceivePort _remotePort = ReceivePort();

void _remote(msg) async {
  if (msg is _Message) {
    if (_remoteHandler == null) {
      final data = msg.content as _BoostrapData;
      _remoteHandler = data.handler;
      _callerPort = data.sendPort;
      _remotePort.listen(_remote);
      _callerPort.send(_Message(msg.id, _remotePort.sendPort));
    } else {
      Object result;
      try {
        result = _remoteHandler.handle(msg.content);
      } catch (e) {
        result = e;
      }
      while (result is Future) {
        result = await result;
      }
      if (result is Stream) {
        await for (var item in result) {
          _callerPort.send(_Message<Object>(msg.id, item));
        }
        // actor doesn't know we're done if we don't tell it explicitly
        _callerPort.send(_Message<Object>(msg.id, #actors_stream_done));
      } else {
        _callerPort.send(_Message<Object>(msg.id, result));
      }
    }
  } else {
    throw StateError('Unexpected message: $msg');
  }
}
