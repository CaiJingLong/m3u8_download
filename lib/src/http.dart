import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:path/path.dart';

final httpClient = Client();

bool _isInitCache = false;
late Map<String, dynamic> _map;

Future<String> getBody(String url, String outputPath) async {
  final configFile = File(join(outputPath, 'cache.json'));

  if (!_isInitCache) {
    if (!configFile.existsSync()) {
      configFile.createSync(recursive: true);
      configFile.writeAsStringSync('{}');
    }

    _map = json.decode(configFile.readAsStringSync());

    _isInitCache = true;
  }

  final map = _map;

  final cache = map[url];

  if (cache != null) {
    return cache;
  }

  final request = Request('GET', Uri.parse(url));
  final response = await httpClient.send(request);

  String body;
  if (response.isRedirect) {
    final location = response.headers['location'];
    body = await getBody(location!, outputPath);
  } else {
    body = await response.stream.bytesToString();
  }

  map[url] = body;
  configFile.writeAsStringSync(json.encode(map));

  return body;
}

void clearCache(String outputPath) {
  final configFile = File(join(outputPath, 'cache.json'));
  if (configFile.existsSync()) {
    configFile.deleteSync();
  }
}
