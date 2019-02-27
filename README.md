# actors

`actors` is a library that enables the use of the Actors Model in Dart.

It is a thin wrapper around Dart's `Isolate` that makes them much easier to use.

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
