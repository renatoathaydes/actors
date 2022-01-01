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
  final isolateName = Isolate.current.debugName ?? '';
  if (isolateName.isEmpty || isolateName == 'main') {
    return 'Actor-${_actorCount++}';
  }
  return '$isolateName-Actor-${_actorCount++}';
}
