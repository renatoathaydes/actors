## Next Release

- added `toSendable` to `Actor` so that the Actor can be sent to another Actor via its `Sendable` object.
- added method `sendToAll` to `ActorGroup`.

## 0.9.0

- require Dart SDK 3.0+.
- added `init` method to `Handler` to allow for the initialization of non-sendable state.

## 0.8.4

- require Dart SDK 2.16.
- docs improvements.

## 0.8.3

- added `close` method to `Handler` to facilitate resource management.

## 0.8.2

- apply workaround to remove Dart bogus warning, see https://github.com/dart-lang/sdk/issues/48090.

## 0.8.1

- upgraded to Dart 2.15.0 to use updated Isolate API.

## 0.8.0

- set debug name for `Isolate` backing an `Actor` (starts with `Actor-0`, then `Actor-1` and so on).
- completed separation of `actors` API from actual implementation with `Isolate`.
  In the future, this may allow implementing actors with web workers.

## 0.7.0

- Null-safety stable relese.

## 0.7.0-nullsafety.1

> This version should only be used if you're
> [migrating to Dart with null-safety](https://dart.dev/null-safety/migration-guide).

- Allow Actors to send and return nullable types.

## 0.7.0-nullsafety.0

> This version should only be used if you're
> [migrating to Dart with null-safety](https://dart.dev/null-safety/migration-guide).

- Enabled null-safety.

## 0.6.1

- Propagate stacktrace to caller on Exception inside an Actor.

## 0.6.0

- Stopped exposing Isolate from Actor. This should allow a web implementation in the future.
- Convert remote Error into a RemoteErrorException to be able to send it back to caller.
- Fixed close() method so that Actors actually drop all subscriptions and allow the system to die when all Actors are closed. 

## 0.5.0

- Created StreamActor to support Actors that return Streams.
- Removed AllHandleWithNAcks GroupStrategy.
- Created MultiHandler GroupStrategy, better implementation and more flexible than AllHandleWithNAcks.
- Allow external implementations of GroupStrategy to be used.
- Deprecated 'isolate' field in Actor. Will remove in the next version to allow web implementation.

## 0.4.0

- Allow all Messenger subtypes to be created from a function.
- Added support for GroupStrategy, so ActorGroup can have different ways to send messages to actors.
- Created RoundRobinGroupStrategy.
- Created AllHandleWithNAcks.
- All Messenger sub-types are now closeable.
- Changed return type of Messenger.send from Future to FutureOr. 

## 0.3.0

- Added ActorGroup.
- Added LocalMessenger.

## 0.2.0

- Lighter message representation for smaller overhead.

## 0.1.0

- Initial version, created by Stagehand.
- Implemented basic functionaliy of an Actor.