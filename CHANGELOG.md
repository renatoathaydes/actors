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