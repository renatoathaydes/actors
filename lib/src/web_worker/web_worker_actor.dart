import 'dart:async';
import 'dart:html' show Worker, window;

import '../actors_base.dart' show jsWorker;
import '../message.dart';

/// This is a non-exported type that stubs the needed methods to implement
/// an Actor.
///
/// The implementations are based on [Isolate] on Dart VM, and [WebWorker]
/// in the browser.
class ActorImpl {
  final Receiver receiver;

  ActorImpl(this.receiver);

  static ActorImpl create() => ActorImpl(Receiver.create());

  Sender get sender => receiver.sender;

  Stream<Message> get answerStream => receiver.answerStream;

  void spawn(void Function(Message) entryPoint, Message message) {
    // FIXME entryPoint is not needed?? How to run that in the worker?
    // FIXME BootstrapMessage includes the sender, sending that seems to not work
    // sender.send(message);
    sender.send('start please');
  }

  Future<void> close() async {
    receiver.close();
  }
}

class Sender {
  final Worker _worker;

  Sender(this._worker);

  void send(Object message) {
    _worker.postMessage(message);
  }
}

class Receiver {
  final Worker _worker;
  final Sender sender;

  Receiver(this._worker, this.sender);

  static Receiver create() {
    final worker = Worker(jsWorker);
    final sender = Sender(worker);
    return Receiver(worker, sender);
  }

  Stream<Message> get answerStream {
    return _worker.onMessage
        .map((event) => event.data)
        .cast<Message>()
        .asBroadcastStream();
  }

  StreamSubscription listen(void Function(Object?)? onData) {
    return _worker.onMessage.listen(onData);
  }

  void close() {
    _worker.terminate();
  }
}

void main() {
  print('RUNNING WORKER');
  window.onMessage.listen((event) {
    print('WORKER GOT MESSAGE: ${event.data}');
  });
}
