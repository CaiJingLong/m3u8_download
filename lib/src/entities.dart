import 'dart:io';
import 'dart:typed_data';

import 'package:dext/dext.dart';
import 'package:http/http.dart';

import 'http.dart';

class TS {
  final String metaText;
  final String srcUrl;
  final String url;

  TS(this.metaText, this.srcUrl, this.url);

  Uri get wholeUri => Uri.parse(srcUrl).resolve(url);

  @override
  String toString() {
    return wholeUri.toString();
  }
}

class Key {
  final String text;
  final String srcUrl;

  Key(
    this.srcUrl,
    this.text,
  );

  late Uint8List _keyContent;
  late String method;
  String? iv;

  Future<void> init() async {
    // #EXT-X-KEY:METHOD=AES-128,URI="key.key"
    // #EXT-X-KEY:METHOD=AES-128,URI=key.key
    // #EXT-X-KEY:METHOD=AES-128,URI="enc.key",IV=0x00000000000000000000000000000000

    final text = this.text.removePrefix('#EXT-X-KEY:');

    final params = text.split(',').map((e) {
      final kv = e.split('=');
      return MapEntry(kv[0], kv[1]);
    }).toMap();

    method = params['METHOD']!;
    final keyUrl = params['URI']!.removePrefix('"').removeSuffix('"');
    final wholeUrl = Uri.parse(srcUrl).resolve(keyUrl).toString();
    _keyContent = await httpClient.readBytes(Uri.parse(wholeUrl));

    iv = params['IV'];
  }

  @override
  String toString() {
    return text;
  }

  Future<File> download(String path) async {
    final file = File(path);
    await init();
    file.writeAsBytesSync(_keyContent);

    return file;
  }

  String getText(File keyFile) {
    final sb = StringBuffer();

    sb.write('#EXT-X-KEY:METHOD=$method,URI="${keyFile.absolute.uri}"');

    if (iv != null) {
      sb.write(',IV=$iv');
    }

    return sb.toString();
  }

  String resolveMetaText() {
    // replace URI to whole https url
    final regex = RegExp(r'URI="(.*)"');
    final uri = regex.firstMatch(text)!.group(1)!;
    final wholeUrl = Uri.parse(srcUrl).resolve(uri).toString();
    final newText = text.replaceFirst(regex, 'URI="$wholeUrl"');
    return newText;
  }
}

class M3u8 {
  final List<TS> tsList;
  final Key? key;
  final String srcUrl;

  M3u8({
    required this.tsList,
    required this.srcUrl,
    this.key,
  });

  static Future<M3u8> from(String url) async {
    final Request request = Request('GET', Uri.parse(url));
    request.followRedirects = false;
    final response = await httpClient.send(request);

    if (response.isRedirect) {
      final location = response.headers['location'];
      return from(location!);
    }

    final body = await response.stream.bytesToString();

    return parse(url, body);
  }

  static Future<M3u8> parse(String httpUrl, String body) async {
    // 获取文件列表
    final lines = body.split('\n');

    final tsList = <TS>[];
    Key? key;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      if (line.endsWith('.ts')) {
        final metaText = lines[i - 1].trim();
        tsList.add(TS(metaText, httpUrl, line));
      } else if (line.endsWith('.m3u8')) {
        final url = line;
        final wholeUrl = Uri.parse(httpUrl).resolve(url).toString();
        final m3u8 = await M3u8.from(wholeUrl);
        tsList.addAll(m3u8.tsList);
        key ??= m3u8.key;
      }

      if (line.startsWith('#EXT-X-KEY:')) {
        key = Key(httpUrl, line);
      }
    }

    return M3u8(srcUrl: httpUrl, tsList: tsList, key: key);
  }

  @override
  String toString() {
    final tsText = tsList.join('\n');
    return tsText;
  }
}
