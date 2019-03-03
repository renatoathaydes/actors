import 'actors_base.dart';

/// A simple implementation of [Messenger] that runs in the local [Isolate].
///
/// The message is handled by the [Handler] (provided in the constructor)
/// asynchronously in the event queue.
class LocalMessenger<M, A> with Messenger<M, A> {
  final Handler<M, A> _handler;

  LocalMessenger(this._handler);

  @override
  Future<A> send(M message) {
    return Future(() => _handler.handle(message));
  }
}
