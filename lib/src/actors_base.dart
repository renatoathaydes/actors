import 'dart:async';
import 'dart:isolate';

import 'stub_actor.dart'
    if (dart.library.io) 'isolate/isolate_actor.dart'
    if (dart.library.html) 'web_worker/web_worker_actor.dart';

final _actorTerminate = 1;

class _Message {
  final int id;
  final Object content;
  final String? stackTraceString;

  const _Message(this.id, this.content, {this.stackTraceString});

  StackTrace? get stacktrace => stackTraceString != null
      ? StackTrace.fromString(stackTraceString!)
      : null;

  bool get isError => stackTraceString != null;
}

class _BoostrapData<M extends Object, A extends Object> {
  final SendPort sendPort;
  final Handler<M, A> handler;

  const _BoostrapData(this.sendPort, this.handler);
}

/// An [Exception] that holds information about an [Error] thrown in a remote
/// [Isolate].
///
/// This is necessary because [Error] instances cannot be moved between different
/// isolates.
///
/// An [Error] thrown by an [Actor] when handling a message is turned into
/// a [RemoteErrorExcpeption] on the calling isolate. All information about the
/// error, including its String-formatted stack-trace, is available in the
/// resulting [RemoteErrorException] in the [errorAsString] field.
class RemoteErrorException implements Exception {
  final String errorAsString;

  const RemoteErrorException(this.errorAsString);

  @override
  String toString() => 'RemoteErrorException{$errorAsString}';
}

/// An Exception that indicates that the channel of communication with a
/// [Messenger] has been broken.
///
/// This typically occurs when an [Actor] is closed while it still has pending
/// messages being processed.
class MessengerStreamBroken implements Exception {
  const MessengerStreamBroken();
}

typedef HandlerFunction<M, A> = FutureOr<A> Function(M message);

/// A [Handler] implements the logic to handle messages.
mixin Handler<M extends Object, A extends Object> {
  /// Handle a message, optionally sending an answer back to the caller.
  FutureOr<A> handle(M message);
}

class _HandlerOfFunction<M extends Object, A extends Object>
    with Handler<M, A> {
  final HandlerFunction<M, A> _function;

  const _HandlerOfFunction(this._function);

  @override
  FutureOr<A> handle(M message) => _function(message);
}

/// Wrap a [HandlerFunction] into a [Handler] object.
Handler<M, A> asHandler<M extends Object, A extends Object>(
        HandlerFunction<M, A> handlerFunction) =>
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
class Actor<M extends Object, A extends Object> with Messenger<M, A> {
  late final ActorImpl _isolate;
  final ReceivePort _localPort;
  late final Stream<_Message> _answerStream;
  late final Future<SendPort> _sendPort;
  int _currentId = -2 ^ 30;
  bool _isClosed = false;

  /// Creates an [Actor] that handles messages with the given [Handler].
  ///
  /// Use the [of] constructor to wrap a function directly.
  Actor(Handler<M, A> handler) : _localPort = ReceivePort() {
    _validateGenericType();

    _answerStream = _localPort.cast<_Message>().asBroadcastStream();
    final id = _currentId++;
    _sendPort = _waitForRemotePort(id);
    _isolate = ActorImpl()
      ..spawn(
          _remote, _Message(id, _BoostrapData(_localPort.sendPort, handler)));
  }

  /// Creates an [Actor] based on a handler function.
  Actor.of(HandlerFunction<M, A> handler) : this(asHandler(handler));

  void _validateGenericType() {
    if (A.toString().startsWith('Stream<')) {
      throw StateError(
          'Actor cannot return a Stream. Use StreamActor instead.');
    }
  }

  Future<SendPort> _waitForRemotePort(int id) {
    return _answerStream
        .firstWhere((answer) => (answer.id == id))
        .then((msg) => msg.content as SendPort);
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
  FutureOr<A> send(M message) {
    final id = _currentId++;
    final completer = Completer<A>();
    final futureAnswer = _answerStream.firstWhere((m) => m.id == id);
    _sendPort.then((s) => s.send(_Message(id, message)));
    futureAnswer.then((_Message answer) {
      if (answer.isError) {
        completer.completeError(answer.content, answer.stacktrace);
      } else {
        completer.complete(answer.content as A);
      }
    }, onError: (e, StackTrace stackTrace) {
      completer.completeError(const MessengerStreamBroken(), stackTrace);
    });
    return completer.future;
  }

  @override
  FutureOr close() async {
    if (_isClosed) return;
    _isClosed = true;
    final ack = _answerStream
        .firstWhere((msg) => msg.content == #actor_terminated)
        .timeout(const Duration(seconds: 5),
            onTimeout: () => const _Message(0, #timeout));
    (await _sendPort).send(_actorTerminate);
    await ack;
    _localPort.close();
    await _isolate.close();
  }
}

/// An [Actor] that has the ability to return a [Stream], rather than only
/// a single object.
///
/// This can be used to for "push" communication, where an [Actor] is able to,
/// from a different [Isolate], send many messages back to the caller, which
/// can listen to messages using the standard [Stream] API.
class StreamActor<M extends Object, A> extends Actor<M, Stream<A>> {
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
  Stream<A> send(M message) {
    final id = _currentId++;
    final controller = StreamController<A>();
    _answerStream
        .where((m) => m.id == id)
        .takeWhile((m) => m.content != #actors_stream_done)
        .listen((answer) {
      final content = answer.content;
      if (answer.isError) {
        controller.addError(content, answer.stacktrace);
      } else {
        controller.add(content as A);
      }
    }, onDone: controller.close);
    _sendPort.then((s) => s.send(_Message(id, message)));
    return controller.stream;
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

class _RemoteState {
  late final Handler remoteHandler;
  late final SendPort callerPort;
  bool isInitialized = false;
}

final _remoteState = _RemoteState();
final _remotePort = ReceivePort();

void _remote(msg) async {
  if (_actorTerminate == msg) {
    // we can only receive this message once the RemoteState has been initialized
    _remoteState.callerPort.send(_Message(0, #actor_terminated));
    await Future(_remotePort.close);
  } else if (msg is _Message) {
    if (!_remoteState.isInitialized) {
      final data = msg.content as _BoostrapData;
      _remoteState.remoteHandler = data.handler;
      _remoteState.callerPort = data.sendPort;
      _remoteState.isInitialized = true;
      _remotePort.listen(_remote);
      _remoteState.callerPort.send(_Message(msg.id, _remotePort.sendPort));
    } else {
      Object result;
      StackTrace? trace;
      var isError = false;
      try {
        result = _remoteState.remoteHandler.handle(msg.content);
        while (result is Future<Object>) {
          result = await result;
        }
      } catch (e, _trace) {
        result = e;
        isError = true;
        trace = _trace;
      }

      if (!isError && result is Stream) {
        try {
          await for (var item in result) {
            _remoteState.callerPort.send(_Message(msg.id, item as Object));
          }
          // actor doesn't know we're done if we don't tell it explicitly
          result = #actors_stream_done;
        } catch (e, _trace) {
          result = e;
          isError = true;
          trace = _trace;
        }
      }
      if (isError && result is Error) {
        // Error has a stacktrace which we cannot send back, so turn the error
        // into an String representation of it so we can send it
        result = RemoteErrorException('$result');
      }
      _remoteState.callerPort
          .send(_Message(msg.id, result, stackTraceString: trace?.toString()));
    }
  } else {
    throw StateError('Unexpected message: $msg');
  }
}
