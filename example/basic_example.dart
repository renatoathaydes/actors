import 'dart:io';
import 'dart:isolate';

import 'package:actors/actors.dart';

String withIso(message) => '${Isolate.current.hashCode} - $message';

String sayHi(String name) => withIso('Hi ${name}!');

void main() async {
  print(withIso('main'));
  final actor = Actor.of(sayHi);
  print(await actor.send(Platform.environment['USER'] ?? 'anonymous'));
  await actor.close();
}
