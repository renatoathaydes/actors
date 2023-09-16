import 'dart:async';

import 'message.dart';
import 'sendable.dart';

/// This is a non-exported type that stubs the needed methods to implement
/// an Actor.
///
/// The implementations are based on [Isolate] on Dart VM, and [WebWorker]
/// in the browser.
class ActorImpl {
  static ActorImpl create() {
    throw Exception();
  }

  /// Sender is the object that gets sent to another actor so that the other
  /// actor can send messages back to this one.
  final Sender sender = throw Exception();

  /// A [Stream] of answers sent by other actors to this actor via [sender].
  ///
  /// This property is only accessed after a call to [spawn].
  final Stream<Message> answerStream = throw Exception();

  /// Spawn an Actor that executes the provided function, immediately
  /// receiving the given message.
  void spawn(void Function(Message) entryPoint, Message message) {}

  /// Close this Actor.
  Future<void> close() async {}

  /// Create a [Sendable] object that can be sent to other actors and be used
  /// by them to send messages back to this actor.
  Sendable<M, A> createSendable<M, A>() => throw Exception();
}

mixin Sender {
  void send(AnyMessage message) {}
}

mixin Receiver {
  static Receiver create() {
    throw Exception();
  }

  final Sender sender = throw Exception();

  Future get first => throw Exception();

  StreamSubscription listen(void Function(AnyMessage) onData) {
    throw Exception();
  }

  void close() {}
}
