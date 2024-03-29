import 'dart:async';
import 'dart:math' show pow;

import 'answer_handler.dart';
import 'message.dart';
import 'sendable.dart';
import 'stub_actor.dart'
    if (dart.library.io) 'isolate/isolate_actor.dart'
    if (dart.library.html) 'web_worker/web_worker_actor.dart';

class _BoostrapData<M, A> {
  final Sender sender;
  final Handler<M, A> Function() handler;

  const _BoostrapData(this.sender, this.handler);
}

/// An [Exception] that holds information about an [Error] thrown in a remote
/// [Isolate].
///
/// This is necessary because [Error] instances cannot be moved between different
/// isolates.
///
/// An [Error] thrown by an [Actor] when handling a message is turned into
/// a [RemoteErrorException] on the calling isolate. All information about the
/// error, including its String-formatted stack-trace, is available in the
/// resulting [RemoteErrorException] in the [errorAsString] field.
class RemoteErrorException implements Exception {
  final String errorAsString;

  const RemoteErrorException(this.errorAsString);

  @override
  String toString() => 'RemoteErrorException{$errorAsString}';
}

/// An [Exception] that is thrown by an [Actor] if it fails to initialize.
///
/// Whenever the Actor's [Actor.send()] method is called, it may result in
/// this Exception because there's no way to wait for successful initialization
/// directly. However, if at least one successful message is received, then
/// it is guaranteed that this Exception will never be thrown by `actors`.
final class ActorInitializationException implements Exception {
  final Object cause;
  final StackTrace stackTrace;

  const ActorInitializationException(this.cause, this.stackTrace);
}

typedef HandlerFunction<M, A> = FutureOr<A> Function(M message);

/// A [Handler] implements the logic to handle messages.
///
/// Classes that might be used as [Actor]s or other [Messenger]s must
/// implement this mixin.
mixin Handler<M, A> {
  /// Initialize the state of this [Handler].
  ///
  /// Any state that cannot be sent to another Isolate must be initialized
  /// in this method rather than in the Actor's constructor.
  ///
  /// This method must not be called directly on an [Actor] instance, as the
  /// framework itself will invoke it on the remote [Isolate] before the actor
  /// is allowed to handle messages sent to it.
  FutureOr<void> init() async {}

  /// Handle a message, optionally sending an answer back to the caller.
  FutureOr<A> handle(M message);

  /// Close this [Handler].
  /// This method must not be called by application code.
  /// The `actors` library will call this when an [Actor] that uses this
  /// [Handler] is closed.
  FutureOr<void> close() {}
}

class _HandlerOfFunction<M, A> with Handler<M, A> {
  final HandlerFunction<M, A> _function;

  const _HandlerOfFunction(this._function);

  @override
  FutureOr<A> handle(M message) => _function(message);
}

/// Wrap a [HandlerFunction] into a [Handler] object.
Handler<M, A> Function() asHandler<M, A>(
        HandlerFunction<M, A> handlerFunction) =>
    () => _HandlerOfFunction(handlerFunction);

/// A [Messenger] can send a message and receive an answer asynchronously.
mixin Messenger<M, A> {
  /// Send a message and get a [Future] to receive the answer at some later
  /// point in time, asynchronously.
  FutureOr<A> send(M message);

  /// Close this [Messenger].
  ///
  /// After this method is called, this Messenger should no longer respond
  /// to any messages. It's an error to send messages to a closed Messenger.
  FutureOr<void> close();
}

/// An [Actor] is an entity that can send messages to a [Handler]
/// running inside a Dart [Isolate].
///
/// It can be seen as the local view of the isolated [Handler] that handles
/// messages sent via the [Actor], communicating
/// with the associated [Isolate] in a transparent manner.
///
/// [Actor]s are mapped 1-1 to [Isolate]s in the Dart VM, so
/// the limitations of [Isolate]s also apply to [Actor]s:
///
/// * messages sent to [Actor]s must be copied into the [Isolate] the [Actor]
///   is running on unless the DartVM can infer the message is immutable.
/// * not all Dart objects can be sent to an Actor, see the limitations in
/// [SendPort.send](https://api.dart.dev/stable/dart-isolate/SendPort/send.html)
/// for details.
///
/// Notice that an [Actor] cannot return a [Stream] of any kind, only a single
/// [FutureOr] of type [A]. To return a [Stream], use [StreamActor] instead.
///
/// On the web, Actors do not have an isolated environment. For this reason,
/// Actors that rely on mutable global variables being "isolated" to themselves
/// are not fully portable.
class Actor<M, A> with Messenger<M, A> {
  late final ActorImpl _actorImpl;
  late final Stream<Message> _answerStream;
  late final Future<Sender> _sender;
  num _currentId = -pow(2, 16);
  bool _isClosed = false;

  /// Creates an [Actor] that handles messages with the given [Handler].
  ///
  /// Prefer to use the [Actor.create] constructor to avoid instantiating the
  /// [Handler] locally, unnecessarily.
  ///
  /// Use the [of] constructor to wrap a function directly.
  Actor(Handler<M, A> handler) : this.create(() => handler);

  /// Creates an [Actor] that handles messages with the [Handler] returned
  /// by the [createHandler] function.
  ///
  /// Use the [of] constructor to wrap a function directly.
  Actor.create(Handler<M, A> Function() createHandler) {
    _validateGenericType();

    final id = _currentId++;
    _actorImpl = ActorImpl.create();

    _actorImpl.spawn(
        _remote, Message(id, _BoostrapData(_actorImpl.sender, createHandler)));

    _answerStream = _actorImpl.answerStream;
    _sender = _waitForRemotePort(id);
  }

  /// Creates an [Actor] based on a handler function.
  Actor.of(HandlerFunction<M, A> handler) : this.create(asHandler(handler));

  /// A handle to this [Actor] which can be sent to other actors.
  ///
  /// Unlike an [Actor], a [Sendable] cannot be closed, hence only the original
  /// creator of an [Actor] is able to close it.
  Future<Sendable<M, A>> toSendable() async => SendableImpl(await _sender);

  void _validateGenericType() {
    if (A.toString().startsWith('Stream<')) {
      throw StateError(
          'Actor cannot return a Stream. Use StreamActor instead.');
    }
  }

  Future<Sender> _waitForRemotePort(num id) async {
    final msg = await _answerStream.firstWhere((answer) => (answer.id == id),
        orElse: () => throw const MessengerStreamBroken());
    if (msg.isError) {
      unawaited(_actorImpl.close());
      throw ActorInitializationException(msg.content!, msg.stacktrace!);
    }
    return msg.content as Sender;
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
    final futureAnswer = _answerStream.firstWhere((m) => m.id == id,
        // will not await for answer unless init() succeeded, so delay throw
        orElse: () =>
            Message(0, const MessengerStreamBroken(), stackTraceString: ''));
    final sendFuture = _sender.then((s) => s.send(Message(id, message)),
        // force sendFuture to only fail asynchronously
        onError: (e) async => throw e);
    return handleAnswer(sendFuture, futureAnswer);
  }

  /// Close this [Actor].
  ///
  /// This method awaits for the underlying [Handler] to close,
  /// but remote errors are not currently propagated to the caller
  /// (i.e. even if the [Handler] throws an error on close, this method
  /// will NOT throw).
  ///
  /// Notice that when backed by a Dart Isolate, the Isolate will not
  /// terminate until the [Handler]'s close method completes,
  /// successfully or not.
  @override
  FutureOr<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    final ack = _answerStream.firstWhere(
        (msg) => msg.content == #actor_terminated,
        orElse: () => const Message(0, null));
    (await _sender).send(TerminateActor.singleton);
    await ack;
    await _actorImpl.close();
  }
}

/// An [Actor] that has the ability to return a [Stream], rather than only
/// a single object, for each message it receives.
///
/// This can be used to for "push" communication, where an [Actor] is able to,
/// from a different [Isolate], send many messages back to the caller, which
/// can listen to messages using the standard [Stream] API.
class StreamActor<M, A> extends Actor<M, Stream<A>> {
  /// Creates a [StreamActor] that handles messages with the given [Handler].
  ///
  /// Prefer to use the [StreamActor.create] constructor to avoid instantiating the
  /// [Handler] locally, unnecessarily.
  ///
  /// Use the [of] constructor to wrap a function directly.
  StreamActor(Handler<M, Stream<A>> handler) : super(handler);

  /// Creates a [StreamActor] that handles messages with the [Handler]
  /// returned by [createHandler].
  ///
  /// Use the [of] constructor to wrap a function directly.
  StreamActor.create(Handler<M, Stream<A>> Function() createHandler)
      : super.create(createHandler);

  /// Creates a [StreamActor] based on a handler function.
  StreamActor.of(HandlerFunction<M, Stream<A>> handler)
      : this.create(asHandler(handler));

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
        .takeWhile((m) => m.content != #_actors_stream_done)
        .listen((answer) {
      final content = answer.content;
      if (answer.isError) {
        controller.addError(content!, answer.stacktrace);
      } else {
        controller.add(content as A);
      }
    }, onDone: controller.close);
    _sender.then((s) => s.send(Message(id, message)));
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
  final Handler remoteHandler;
  final Sender sender;
  final receiver = Receiver.create();

  _RemoteState(_BoostrapData data)
      : remoteHandler = data.handler(),
        sender = data.sender;

  void receive(AnyMessage msg) async {
    switch (msg) {
      case Message msg:
        await _handle(msg.content, sender, msg.id);
      case OneOffMessage msg:
        await _handle(msg.content, msg.sender, -1);
      case TerminateActor.singleton:
        // we can only receive this message once the RemoteState has been initialized
        try {
          await remoteHandler.close();
        } finally {
          sender.send(const Message(0, #actor_terminated));
        }
        await Future(receiver.close);
    }
  }

  Future<void> _handle(Object? messageContent, Sender sender, num id) async {
    dynamic result;
    try {
      result = await remoteHandler.handle(messageContent);
    } catch (e, st) {
      _sendAnswer(sender, id, e, st, true);
      return;
    }
    _sendAnswer(sender, id, result, null, false);
  }
}

void _remote(Message msg) async {
  final remoteState = _RemoteState(msg.content as _BoostrapData);
  try {
    await remoteState.remoteHandler.init();
  } catch (e, st) {
    return remoteState.sender.send(Message(msg.id, _safeToSendException(e),
        stackTraceString: st.toString()));
  }
  remoteState.receiver.listen(remoteState.receive);
  remoteState.sender.send(Message(msg.id, remoteState.receiver.sender));
}

void _sendAnswer(Sender sender, num id, Object? result, StackTrace? trace,
    bool isError) async {
  if (!isError && result is Stream) {
    try {
      await for (var item in result) {
        sender.send(Message(id, item));
      }
      // actor doesn't know we're done if we don't tell it explicitly
      result = #_actors_stream_done;
    } catch (e, st) {
      result = e;
      isError = true;
      trace = st;
    }
  }
  if (isError) {
    result = _safeToSendException(result);
  }
  sender.send(Message(id, result, stackTraceString: trace?.toString()));
}

Object? _safeToSendException(Object? exception) {
  if (exception is Error) {
    // Error has a stacktrace which we cannot send back, so turn the error
    // into an String representation of it so we can send it
    return RemoteErrorException('$exception');
  }
  return exception;
}
