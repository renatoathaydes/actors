import 'actors_base.dart';

/// An [ActorGroup] groups a number of [Actor]s using the same type of
/// [Handler] to handle messages.
///
/// Notice that each [Actor] will have its own instance of the [Handler],
/// and because of that the [Handler]s cannot share any state.
///
/// When a message is sent to an [ActorGroup] it may be handled by
/// any of the [Actor]s in the group.
/// Each [Actor] runs, as usual, in its own [Isolate].
///
/// The strategy to select which [Actor] should handle a given message is
/// currently simple Round-Robin, but this may be changed in the future.
class ActorGroup<M, A> with Messenger<M, A> {
  final int size;
  final List<Actor<M, A>> actors;
  int _index = 0;

  ActorGroup(Handler<M, A> handler, {int size = 6})
      : size = size,
        actors = _buildActors(size, handler);

  static List<Actor<M, A>> _buildActors<M, A>(int size, Handler<M, A> handler) {
    final actors = List<Actor<M, A>>(size);
    for (int i = 0; i < size; i++) {
      actors[i] = Actor(handler);
    }
    return actors;
  }

  @override
  Future<A> send(M message) {
    return actors[_index++ % size].send(message);
  }
}
