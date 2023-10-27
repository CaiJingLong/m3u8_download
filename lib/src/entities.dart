import 'dart:io';
import 'dart:typed_data';

import 'package:dext/dext.dart';

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
    final regex = RegExp(r'URI="(.*)"');
    if (regex.hasMatch(text)) {
      // replace URI to whole https url
      final uri = regex.firstMatch(text)!.group(1)!;
      final wholeUrl = Uri.parse(srcUrl).resolve(uri).toString();
      final newText = text.replaceFirst(regex, 'URI="$wholeUrl"');
      return newText;
    } else {
      // If URI can't be found, return original text.
      return text;
    }
  }
}

class M3u8 {
  final List<TS> tsList;
  final Key? key;
  final String srcUrl;
  final List<String> m3u8List;

  M3u8({
    required this.tsList,
    required this.srcUrl,
    this.key,
    required this.m3u8List,
  });

  static Future<M3u8> from(
    String url,
    String outputPath, {
    List<String>? m3u8List,
  }) async {
    m3u8List ??= [];

    final body = await getBody(url, outputPath);
    return parse(url, body, outputPath, m3u8List: m3u8List);
  }

  static Future<M3u8> parse(
    String httpUrl,
    String body,
    String outputPath, {
    required List<String> m3u8List,
  }) async {
    m3u8List.add(httpUrl);
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
        final m3u8 = await M3u8.from(wholeUrl, outputPath, m3u8List: m3u8List);
        tsList.addAll(m3u8.tsList);
        key ??= m3u8.key;
      }

      if (line.startsWith('#EXT-X-KEY:')) {
        key = Key(httpUrl, line);
      }
    }

    return M3u8(
      srcUrl: httpUrl,
      tsList: tsList,
      key: key,
      m3u8List: m3u8List,
    );
  }

  String get lastM3u8Url {
    return m3u8List.last;
  }

  @override
  String toString() {
    final tsText = tsList.join('\n');
    return tsText;
  }

  Future<String> getLocalM3u8Content(M3u8 m3u8, String outputPath) async {
    // get src text
    final body = await getBody(m3u8.lastM3u8Url, outputPath);
    final srcUri = Uri.parse(m3u8.lastM3u8Url);

    final sb = StringBuffer();
    // replace all url to local path
    final lines = body.split('\n');

    var i = 0;

    for (final line in lines) {
      if (line.startsWith('#EXT-X-KEY')) {
        // replace to whole https url
        if (line.contains('URI=')) {
          // #EXT-X-KEY:METHOD=AES-128,URI="/20220716/HsRDCTFg/500kb/hls/key.key"
          final regex = RegExp(r'URI="(.*)"');
          final uri = regex.firstMatch(line);

          if (uri != null) {
            final wholeUrl = srcUri.resolve(uri.group(1)!).toString();
            final newText = line.replaceFirst(regex, 'URI="$wholeUrl"');
            sb.writeln(newText);
          } else {
            sb.writeln(line);
          }
        } else {
          sb.writeln(line);
        }
      } else if (line.trim().endsWith('.ts')) {
        // replace to local path
        final tsName = '$i.ts';
        i++;
        sb.writeln(tsName);
      } else {
        sb.writeln(line);
      }
    }

    return sb.toString();
  }
}
