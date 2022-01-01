import 'dart:io';
import 'dart:isolate';

import 'package:actors/actors.dart';

String withIsolateName(message) => '[${Isolate.current.debugName}] $message';

String sayHi(String name) => withIsolateName('Hi $name!');

void main() async {
  print(withIsolateName('Running main'));
  final actor = Actor.of(sayHi);
  print(await actor.send(Platform.environment['USER'] ?? 'anonymous'));
  await actor.close();
}
