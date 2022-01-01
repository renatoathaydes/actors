import 'dart:isolate';

class ActorImpl {
  late Future<Isolate> _iso;

  void spawn(void Function(dynamic) entryPoint, message) {
    _iso = Isolate.spawn(entryPoint, message, debugName: _generateName());
  }

  Future<void> close() async {
    (await _iso).kill(priority: Isolate.immediate);
  }
}

int _actorCount = 0;

String _generateName() {
  return "Actor-${_actorCount++}";
}
