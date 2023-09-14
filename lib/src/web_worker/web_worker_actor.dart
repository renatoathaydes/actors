import 'dart:async';

import '../message.dart';

/// This is a non-exported type that stubs the needed methods to implement
/// an Actor.
///
/// The implementations are based on [Isolate] on Dart VM, and [WebWorker]
/// in the browser.
class ActorImpl {
  static ActorImpl create() {
    throw Exception();
  }

  final Sender sender = throw 'Web Actors are not implemented yet!';

  final Stream<Message> answerStream =
      throw 'Web Actors are not implemented yet!';

  void spawn(void Function(Message) entryPoint, Message message) {}

  Future<void> close() async {}
}

mixin Sender {
  void send(Object? message) {
    throw 'Web Actors are not implemented yet!';
  }
}

mixin Receiver {
  static Receiver create() {
    throw 'Web Actors are not implemented yet!';
  }

  final Sender sender = throw 'Web Actors are not implemented yet!';

  StreamSubscription listen(void Function(Object?)? onData) {
    throw 'Web Actors are not implemented yet!';
  }

  Future get first => throw 'Web Actors are not implemented yet!';

  void close() {
    throw 'Web Actors are not implemented yet!';
  }
}
