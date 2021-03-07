import 'dart:isolate';

class ActorImpl {
  late Future<Isolate> _iso;

  void spawn(void Function(dynamic) entryPoint, message) {
    _iso = Isolate.spawn(entryPoint, message);
  }

  Future<void> close() async {
    (await _iso).kill(priority: Isolate.immediate);
  }
}
