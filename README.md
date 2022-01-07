# actors

[![Dartle CI](https://github.com/renatoathaydes/actors/workflows/Dartle%20CI/badge.svg)](https://github.com/renatoathaydes/actors/actions)
[![pub package](https://img.shields.io/pub/v/actors)](https://pub.dev/packages/actors)

`actors` is a library that enables the use of the Actors Model in Dart.

It is a thin wrapper around Dart's `Isolate` (on Flutter and Dart VM)
and Web Workers (on the Web - TODO) that makes them much easier to use.

## Actor

To start an Actor is very easy. You simply create a `Handler` implementing the logic to handle messages within the
Actor's Isolate, then create an `Actor` using it:

```dart
class Two with Handler<int, int> {
  int handle(int n) => n * 2;
}

main() async {
  final actor = Actor(Two());
  print(await actor.send(5)); // 10
  await actor.close();
}
```

If your actor does not maintain internal state, it can also be created from a function:

> Due to limitations of `Isolate`, the function must be a top-level function, i.e. not a lambda. 

```dart
int two(int n) => n * 2;

main() async {
  final actor = Actor.of(two);
  print(await actor.send(5)); // 10
  await actor.close();
}
```

As you can see, an `Actor` can send a message back to the caller asynchronously.

They can also send more than one message by returning a `Stream`:

```dart
// A Handler that returns a Stream must use a StreamActor, not an Actor.
class StreamGenerator with Handler<int, Stream<int>> {
  @override
  Stream<int> handle(int message) {
    return Stream.fromIterable(Iterable.generate(message, (i) => i));
  }
}

main() async {
  // Create an StreamActor from a Handler that returns Stream.
  final actor = StreamActor(StreamGenerator());
  final stream = actor.send(2);
  await for (final item in stream) {
    print(item); // 0, 1
  }
  await actor.close();
}
```

## ActorGroup

`ActorGroup` allows several `Actor` instances to be grouped together, all based on the same `Handler` implementation,
but executed according to one of the available strategies:

* `RoundRobin` - send message to a single `Actor`, alternating which member of the group receives the message.
* `MultiHandler` - send message to `m` `Actor`s, wait for at least `n` successful answers.

`RoundRobing` is appropriate for cases where messages are CPU intensive to handle and there may be many of them.

`MultiHandler` is a way to achieve high reliability by duplicating effort, as not all `Actor`s in the group may
be healthy at all times. Having a few "backups" doing the same work on each message may be a good idea in case one or
more of the expected receivers are likely to fail, as the system will still continue to work without issues as long as
`n` actors remain healthy... Also, by sending the same message to several actors, the message might be received in
 different locations, making it much harder for it to be lost.

```dart
// create a group of 4 actors
final group = ActorGroup(Two(), size: 4);
print(await group.send(5)); // 10
group.close();
```

## Messenger

The `Messenger` mixin is implemented by `Actor`, `ActorGroup`, and also `LocalMessenger`, which runs its `Handler`
in the local `Isolate`.

```dart
Messenger<int, int> messenger;

// a Messenger can be local
messenger = LocalMessenger(Two());
print(await messenger.send(2)); // 4

// or it can be an Actor
messenger = Actor(Two());
print(await messenger.send(3)); // 6
messenger.close();

// or an ActorGroup
messenger = ActorGroup(Two(), size: 2);
print(await messenger.send(4)); // 8
print(await messenger.send(5)); // 10
messenger.close();
```

This makes it possible to write code that works the same whether the message is handled locally or in another `Isolate`.
