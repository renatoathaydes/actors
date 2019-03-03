# actors

`actors` is a library that enables the use of the Actors Model in Dart.

It is a thin wrapper around Dart's `Isolate` that makes them much easier to use.

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
  exit(0);
}
```

As you can see, the `Actor` can send a message back to the caller asynchronously.

Actors expose the `Isolate` they run on. To kill an `Isolate`, and consequently the `Actor`, do the following:

```dart
final isolate = await actor.isolate;
isolate.kill(priority: Isolate.immediate);
```

## ActorGroup

For cases where messages are CPU intensive to handle and there may be many of them, the `ActorGroup` class can be used.
It multiplexes messages to a number of `Actor`s which use the same type of `Handler` to handle messages.

```dart
// create a group of 4 actors
final group = ActorGroup(Two(), size: 4);
print(await group.send(5)); // 10
```
