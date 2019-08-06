import 'dart:async';
import 'dart:isolate';

class _Message {
  final int id;
  final content;
  final bool isError;

  _Message(this.id, this.content, {this.isError = false});
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
///
/// Notice that an [Actor] cannot return a [Stream] of any kind, only a single
/// [FutureOr] of type [A]. To return a [Stream], use [StreamActor] instead.
class Actor<M, A> with Messenger<M, A> {
  Future<Isolate> isolate;
  final ReceivePort _localPort;
  Future<SendPort> _sendPort;
  Stream<_Message> _answerStream;
  int _currentId = -2 ^ 30;

  /// Creates an [Actor] that handles messages with the given [Handler].
  ///
  /// Use the [of] constructor to wrap a function directly.
  Actor(Handler<M, A> handler) : _localPort = ReceivePort() {
    _validateGenericType();
    _answerStream = _answers().asBroadcastStream();

    final id = _currentId++;
    _sendPort = _waitForRemotePort(id);
    isolate = Isolate.spawn(
        _remote, _Message(id, _BoostrapData(_localPort.sendPort, handler)));
  }

  /// Creates an [Actor] based on a handler function.
  Actor.of(HandlerFunction<M, A> handler) : this(asHandler(handler));

  void _validateGenericType() {
    if (A.toString().startsWith('Stream<')) {
      throw StateError(
          "Actor cannot return a Stream. Use StreamActor instead.");
    }
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
  FutureOr<A> send(M message) async {
    final id = _currentId++;
    final future = _answerStream.firstWhere((answer) => answer.id == id);
    (await _sendPort).send(_Message(id, message));
    final result = await future;
    final Object content = result.content;
    if (result.isError) {
      throw content;
    }
    return content as FutureOr<A>;
  }

  FutureOr close() async {
    (await isolate).kill(priority: Isolate.immediate);
  }
}

/// An [Actor] that has the ability to return a [Stream], rather than only
/// a single object.
///
/// This can be used to for "push" communication, where an [Actor] is able to,
/// from a different [Isolate], send many messages back to the caller, which
/// can listen to messages using the standard [Stream] API.
class StreamActor<M, A> extends Actor<M, Stream<A>> {
  /// Creates a [StreamActor] that handles messages with the given [Handler].
  ///
  /// Use the [of] constructor to wrap a function directly.
  StreamActor(Handler<M, Stream<A>> handler) : super(handler);

  /// Creates a [StreamActor] based on a handler function.
  StreamActor.of(HandlerFunction<M, Stream<A>> handler)
      : this(asHandler(handler));

  /// Send a message to the [Handler] this [StreamActor] is based on.
  ///
  /// The message is handled in another [Isolate] and the handler's
  /// response is sent back asynchronously.
  ///
  /// If an error occurs while the [Handler] handles the message,
  /// the returned [Stream] emits an error,
  /// otherwise items provided by the [Handler] are streamed back to the caller.
  @override
  Stream<A> send(M message) async* {
    final id = _currentId++;
    (await _sendPort).send(_Message(id, message));
    await for (final answer
        in _answerStream.where((answer) => answer.id == id)) {
      if (answer.isError) throw answer.content;
      final content = answer.content;
      if (content == #actors_stream_done) {
        break;
      } else {
        yield content as A;
      }
    }
  }

  @override
  void _validateGenericType() {
    // no validation currently
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
      bool isError = false;
      try {
        result = _remoteHandler.handle(msg.content);
        while (result is Future) {
          result = await result;
        }
      } catch (e) {
        result = e;
        isError = true;
      }

      if (!isError && result is Stream) {
        try {
          await for (var item in result) {
            _callerPort.send(_Message(msg.id, item));
          }
          // actor doesn't know we're done if we don't tell it explicitly
          result = #actors_stream_done;
        } catch (e) {
          print("Captured error while looping through stream: $e");
          result = e;
          isError = true;
        }
      }
      _callerPort.send(_Message(msg.id, result, isError: isError));
    }
  } else {
    throw StateError('Unexpected message: $msg');
  }
}
