import 'dart:isolate';

class Message<A> {
  final int id;
  final SendPort port;
  final A content;

  Message(this.id, this.port, this.content);
}

mixin Handler<M, A> {
  A handle(M message);
}

class Actor<M, A> {
  Future<Isolate> isolate;
  ReceivePort _localPort;
  Future<SendPort> _remotePort;
  Stream<Message> _answerStream;
  int _currentId = -2 ^ 30;

  Actor(Handler<M, A> handler) {
    _localPort = ReceivePort();
    _answerStream = _answers().asBroadcastStream();

    final id = _currentId++;
    _remotePort = _waitForRemotePort(id);
    isolate = Isolate.spawn(_remote, Message(id, _localPort.sendPort, handler));
  }

  Future<SendPort> _waitForRemotePort(int id) async {
    final firstAnswer = await _answerStream.firstWhere((msg) => msg.id == id);
    return firstAnswer.port;
  }

  Stream<Message> _answers() async* {
    await for (var answer in _localPort) {
      yield answer as Message;
    }
  }

  Future<A> send(M message) async {
    final id = _currentId++;
    final future = _answerStream.firstWhere((msg) => msg.id == id);
    (await _remotePort).send(Message(id, _localPort.sendPort, message));
    final result = await future;
    final content = result.content;
    if (content is Exception) {
      throw content;
    }
    return content as A;
  }
}

Handler _remoteHandler;
ReceivePort _remotePort = ReceivePort();

void _remote(msg) {
  if (_remoteHandler == null) {
    _remoteHandler = msg.content as Handler;
    _remotePort.listen(_remote);
    msg.port.send(Message(msg.id, _remotePort.sendPort, null));
  } else {
    assert(msg is Message);
    var result;
    try {
      result = _remoteHandler.handle(msg.content);
    } catch (e) {
      result = e;
    }
    msg.port.send(Message(msg.id, null, result));
  }
}
