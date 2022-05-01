/// `actors` is a library that enables the use of the Actors Model in Dart.
///
/// It is a thin wrapper around Dart's [Isolate] that makes them much easier to use.
///
/// An [Actor] can be created either from a simple function or a class that
/// mixes in the [Handler] trait:
///
/// Example:
///
/// ```dart
/// import 'package:actors/actors.dart';
///
/// final functionActor = Actor.of((String message) => "Hi $message");
///
/// class MyHandler with Handler<int, int> {
///   @override
///   Future<int> handle(int message) async => message * 2;
/// }
///
/// final basicActor = Actor(MyHandler());
/// ```
///
/// [Actor] and [Handler] are the main types of this library. However,
/// there are also a few other important types:
///
/// * [Messenger] mixin is meant to provide a higher
/// level abstraction than [Actor], with the same API but without
/// the constraint that the implementation must be fully isolated, or handle
/// the message a single time only.
/// * [ActorGroup] implements [Messenger] and can handle a message using
/// multiple actors, one or more times, depending on its strategy.
/// * [LocalMessenger] handles a message in the local Isolate (i.e. it's
/// equivalent to a simple async function).
library actors;

import 'src/actors_base.dart';
import 'src/actor_group.dart';
import 'src/local_messenger.dart';

export 'src/actors_base.dart';
export 'src/actor_group.dart';
export 'src/local_messenger.dart';
