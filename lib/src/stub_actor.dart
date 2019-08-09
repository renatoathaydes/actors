/// This is a non-exported type that stubs the needed methods to implement
/// an Actor.
///
/// The implementations are based on [Isolate] on Dart VM, and [WebWorker]
/// in the browser.
class ActorImpl {
  void spawn(void Function(dynamic) entryPoint, message) {}

  Future<void> close() async {}
}
