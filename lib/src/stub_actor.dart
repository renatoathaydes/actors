import 'dart:async';

import 'message.dart';

/// This is a non-exported type that stubs the needed methods to implement
/// an Actor.
///
/// The implementations are based on [Isolate] on Dart VM, and [WebWorker]
/// in the browser.
class ActorImpl {
  static ActorImpl create() {
    throw Exception();
  }

  final Sender sender = throw Exception();

  final Receiver receiver = throw Exception();

  final Stream<Message> answerStream = throw Exception();

  void spawn(void Function(Message) entryPoint, Message message) {}

  Future<void> close() async {}
}

mixin Sender {
  void send(Object message) {}
}

mixin Receiver {
  static Receiver create() {
    throw Exception();
  }

  final Sender sender = throw Exception();

  StreamSubscription listen(void Function(Object?)? onData) {
    throw Exception();
  }

  void close() {}
}
