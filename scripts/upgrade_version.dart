import 'dart:io';

void main(List<String> args) {
  final targetFile = File('lib/src/versions.dart');

  final pubspecFile = File('pubspec.yaml');

  final version = pubspecFile
      .readAsStringSync()
      .split('\n')
      .firstWhere((element) => element.startsWith('version:'))
      .split('version:')[1]
      .trim();

  final content = '''
class Versions {
  static String version = '$version';
}
''';

  targetFile.writeAsStringSync(content);
}
