# actors

[![Actors CI](https://github.com/renatoathaydes/actors/workflows/Actors%20Multiplatform%20Build%20and%20Tests/badge.svg)](https://github.com/renatoathaydes/actors/actions)
[![pub package](https://img.shields.io/pub/v/actors)](https://pub.dev/packages/actors)

`actors` is a library that enables the use of the Actors Model in Dart.

It is a thin wrapper around Dart's `Isolate` (on Flutter and Dart VM)
and Web Workers (on the Web - TODO) that makes them much easier to use.

## Actor

To start an Actor is very easy. You create a `Handler` implementing the logic to handle messages within the
Actor's Isolate, then create an `Actor` using it:

```dart
class Accumulator with Handler<int, int> {
  int _value;
  
  Accumulator([int initialValue = 0]): _value = initialValue;
  
  int handle(int n) => _value += n;
}

main() async {
  final actor = Actor(Accumulator(6));
  print(await actor.send(5)); // 11
  await actor.close();
}
```

If your actor does not maintain internal state, it can also be created from a function, or even a lambda:

```dart
int two(int n) => n * 2;

main() async {
  final actor = Actor.of(two);
  print(await actor.send(5)); // 10
  await actor.close();
}
```

As you can see, an `Actor` can send a message back to the caller asynchronously.

They can also send more than one message back by returning a `Stream`:

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

### Actor state

An actor can safely maintain internal state which cannot be reached by any other actors (as it resides in its own Dart Isolate).
The state can include anything, even `Stream`s and open sockets, for example.

However, the actor must not **initialize** anything that cannot be **sent** in a message in its constructor.

> That's because, due to limitations of the Dart programming language, an actor gets created both in the local Isolate
(which is not wanted, but unavoidable) and in its own Isolate (i.e. the _actual actor_). If the actor initialized
> something that cannot be _sent_ in its constructor, the initial message sent to its Isolate would fail to be sent
> because the Actor's `Handler` itself is part of that.

For this reason, it's advisable to initialize the state of an actor in the `Handler`'s `init` method, which has the
advantage of allowing async calls to be used.

For example, an Actor which wraps a `HttpServer` could be initialized as shown below:

```dart
class HttpServerActor with Handler<Message, Answer> {
  late final HttpServer _server;
  final int port;

  // notice that only "sendable" state can be initialized or provided
  // in the constructor.
  HttpServerActor(this.port);

  // this method will only run in the Actor's own Isolate, so we can
  // create non-sendable state.
  @override
  Future<void> init() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    unawaited(_serveRequests());
  }
  
  // ...
}
```

You can see the full example code at [example/stateful_actor_example.dart](example/stateful_actor_example.dart).

If you attempted to initialize the non-sendable field, `_server`, in the constructor, like this:

```dart
class HttpServerActor with Handler<Message, Answer> {
  // this won't work unless the Future is only initialized in the Actor's Isolate,
  // because Future is not Sendable!!
  final Future<HttpServer> _server;
  final int port;

  HttpServerActor(this.port)
      : _server = HttpServer.bind(InternetAddress.loopbackIPv4, port);

  // ...
}
```

You would get an error like the following as you tried to create the _local version_ of `HttpServerActor`:

```
Invalid argument(s): Illegal argument in isolate message: object is unsendable - 
  Library:'dart:async' Class: _Future@4048458 (see restrictions listed at `SendPort.send()` documentation for more information)
    <- Instance of 'HttpServerActor' (from file:///programming/projects/actors/example/stateful_actor_example.dart)
```

This can be hard to understand if you're not aware of how this all works, but hopefully now that you've seen it, if it
ever happens to you, you'll be able to fix it without too much stress!

### Sending an Actor to another Actor

To send an Actor to another Actor is not possible directly, but you can send its `Sendable` object, which can be
obtained by calling `toSendable()` (unfortunately, this does not currently work for `StreamActor`).

> See the [inter_actor_test](test/inter_actor_test.dart) test for an example where an Actor's sender function
> is given to another Actor via its constructor.

This enables a common pattern where many actors are given a reference to another actor which can aggregate their
results in one place.

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

## More examples

* [basic_example.dart](example/basic_example.dart) (the basics of actors)
* [actors_example.dart](example/actors_example.dart) (using actors, groups, streams, local)
* [example-projects/word_count](example-projects/word_count) (utility to count words in files)
