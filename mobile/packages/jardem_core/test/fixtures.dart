import 'dart:convert';
import 'dart:io';

/// Loads a JSON payload captured from the live API (`test/fixtures/*.json`).
dynamic fixture(String name) => jsonDecode(fixtureText(name));

String fixtureText(String name) {
  // `flutter test` runs with the package root as the working directory.
  final file = File('test/fixtures/$name.json');
  return file.readAsStringSync();
}

Map<String, dynamic> fixtureMap(String name) => (fixture(name) as Map).cast<String, dynamic>();
