import 'dart:async';
import 'dart:isolate';

import '../message.dart';

class ActorImpl {
  late Future<Isolate> _iso;

  final Stream<Message> answerStream;
  final Sender sender;
  final Receiver receiver;

  ActorImpl(this.answerStream, this.sender, this.receiver);

  static ActorImpl create() {
    final receiver = Receiver.create();
    final answerStream =
        receiver._receivePort.cast<Message>().asBroadcastStream();
    return ActorImpl(answerStream, receiver.sender, receiver);
  }

  void spawn(void Function(Message) entryPoint, Message message) {
    _iso = Isolate.spawn(entryPoint, message, debugName: _generateName());
  }

  void Function(Object?) createSender() {
    return receiver.sendPort.send;
  }

  Future<void> close() async {
    receiver.close();
    (await _iso).kill(priority: Isolate.immediate);
  }
}

int _actorCount = 0;

String _generateName() {
  // Workaround https://github.com/dart-lang/sdk/issues/48090
  final dynamic isolateNameWorkaround = Isolate.current.debugName;
  final String isolateName = isolateNameWorkaround ?? '';
  if (isolateName.isEmpty || isolateName == 'main') {
    return 'Actor-${_actorCount++}';
  }
  return '$isolateName-Actor-${_actorCount++}';
}

class Sender {
  final SendPort _sendPort;

  Sender(this._sendPort);

  void send(Object message) {
    _sendPort.send(message);
  }
}

class Receiver {
  final ReceivePort _receivePort;
  final Sender sender;

  SendPort get sendPort => _receivePort.sendPort;

  static Receiver create() {
    final receivePort = ReceivePort();
    return Receiver(receivePort, Sender(receivePort.sendPort));
  }

  Receiver(this._receivePort, this.sender);

  void close() {
    _receivePort.close();
  }

  StreamSubscription listen(void Function(Object?)? onData) {
    return _receivePort.listen(onData);
  }
}
