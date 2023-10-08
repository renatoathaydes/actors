import 'dart:async';

import 'answer_handler.dart';
import 'message.dart';
import 'stub_actor.dart'
    if (dart.library.io) 'isolate/isolate_actor.dart'
    if (dart.library.html) 'web_worker/web_worker_actor.dart';

/// A handle to an [Actor] which can be sent to other actors.
///
/// Unlike an [Actor], a [Sendable] cannot be closed, hence only the original
/// creator of an [Actor] is able to close it.
mixin Sendable<M, A> {
  /// Send a message and get a [Future] to receive the answer at some later
  /// point in time, asynchronously.
  Future<A> send(M message);
}

/// Internal implementation of [Sendable].
class SendableImpl<M, A> with Sendable<M, A> {
  final Sender _sender;

  SendableImpl(this._sender);

  @override
  Future<A> send(M message) async {
    final receiver = Receiver.create();
    final answer = receiver.first;
    _sender.send(OneOffMessage(receiver.sender, message));
    return handleAnswer(answer.then((m) => m as Message), Completer<A>());
  }
}
