import 'dart:io' show exit;

import 'package:actors/actors.dart';

class Two with Handler<int, int> {
  int handle(int n) => n * 2;
}

main() async {
  final actor = Actor(Two());
  print(await actor.send(5)); // 10
  print(await actor.send(6)); // 12
  print(await actor.send(7)); // 14
  print(await actor.send(8)); // 16
  exit(0);
}
