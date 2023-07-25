import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dext/dext.dart';
import 'package:http/http.dart';

late String supportedProtocol;
late bool removeTemp;
late int threads;
late bool verbose;

void _verbose(Object? object) {
  if (verbose) {
    _log(object);
  }
}

void _log(Object? object) {
  print(object);
}

class _RunStopWatch {
  int? total;
  int? prepare;
  int? download;
  int? merge;
  int? clean;

  void _showTime(String tag, int? time) {
    if (time != null) {
      final duration = Duration(milliseconds: time);
      _log('The $tag time: $duration');
    }
  }

  void logTime() {
    _log('\nThe runtime:');
    _showTime('prepare', prepare);
    _showTime('download', download);
    _showTime('merge', merge);
    _showTime('clean', clean);
    _showTime('total', total);
  }
}

final _runtime = _RunStopWatch();

Future<void> main(List<String> args) async {
  final stopwatch = Stopwatch();
  stopwatch.start();
  final runner = M3u8CommandRunner(
    'm3u8_download',
    'Download m3u8 and merge to mp4',
  );

  await runner.run(args);
  stopwatch.stop();
  _runtime.total = stopwatch.elapsedMilliseconds;

  _runtime.logTime();
}

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
    _keyContent = await _httpClient.readBytes(Uri.parse(wholeUrl));

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

final _httpClient = Client();

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
    final response = await _httpClient.send(request);

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

String getNotRepeatPath(String outputPath) {
  final realPath = '$outputPath.mp4';

  final file = File(realPath);

  if (!file.existsSync()) {
    return outputPath;
  }

  var index = 2;
  while (true) {
    final newOutputPath = '$outputPath-$index';
    final dir = '$newOutputPath.mp4';
    final file = File(dir);
    if (file.existsSync()) {
      index++;
    } else {
      return newOutputPath;
    }
  }
}

class DownloadTask {
  final Uri uri;
  final String outputPath;

  DownloadTask(this.uri, this.outputPath);
}

typedef VoidCallback = void Function();

class DownloadManager {
  final List<DownloadTask> _tasks = [];

  void addTask(DownloadTask task) {
    _tasks.add(task);
  }

  var runningCount = 0;

  var totalCount = 0;

  var finishTask = 0;

  var totalDownloadedBytes = 0;
  final stopwatch = Stopwatch();

  Future<void> start() async {
    stopwatch.start();
    final Completer<void> result = Completer();
    totalCount = _tasks.length;
    Timer.periodic(Duration(milliseconds: 50), (timer) {
      download(() {
        timer.cancel();
        result.complete();
      });
    });

    return result.future;
  }

  Future<void> download([VoidCallback? onDownloadFinish]) async {
    if (finishTask == totalCount) {
      onDownloadFinish?.call();
      return;
    }
    if (_tasks.isNotEmpty) {
      while (runningCount < threads) {
        runningCount++;
        if (_tasks.isEmpty) {
          break;
        }
        final task = _tasks.removeAt(0);
        downloadFile(task);
      }
    }
  }

  String formatSpeed() {
    var downloadSpeed =
        totalDownloadedBytes / stopwatch.elapsed.inMilliseconds * 1000;

    final unit = ['bytes', 'KB', 'MB', 'GB', 'TB', 'PB'];

    var index = 0;

    while (downloadSpeed > 1024) {
      downloadSpeed /= 1024;
      index++;
    }
    final unitText = unit[index];
    return '${downloadSpeed.toStringAsFixed(2)} $unitText/s';
  }

  Future<void> downloadFile(DownloadTask task) async {
    final uri = task.uri;
    final outputPath = task.outputPath;

    final file = File(outputPath);
    if (file.existsSync()) {
      _log('Skip download: $uri');
    } else {
      final request = Request('GET', uri);
      final response = await _httpClient.send(request);

      await file.create(recursive: true);
      final sink = file.openWrite();
      final bytes = await response.stream.toBytes();
      totalDownloadedBytes += bytes.length;

      sink.add(bytes);
      await sink.flush();
      await sink.close();
    }

    _tasks.remove(task);
    runningCount--;
    finishTask++;

    final progress = finishTask / totalCount;
    final progressText = (progress * 100).toStringAsFixed(2);
    final downloadSpeedText = formatSpeed();
    _log('Downloaded: $uri, download progress: $progressText%,'
        ' $downloadSpeedText');
  }
}

Future<void> downloadM3u8(
  M3u8 m3u8,
  String outputPath,
  String outputMediaPath,
) async {
  final manager = DownloadManager();
  for (var i = 0; i < m3u8.tsList.length; i++) {
    final ts = m3u8.tsList[i];

    final uri = ts.wholeUri;
    final tmpName = '$outputPath/$i.ts';

    manager.addTask(DownloadTask(uri, tmpName));
  }

  await manager.start();
}

Future<void> mergeTs(
  M3u8 m3u8,
  String outputPath,
  String outputMediaPath,
) async {
  final m3u8FilePath = '$outputPath/index.m3u8';

  final m3u8Buffer = StringBuffer();

  // write header
  m3u8Buffer.writeln('#EXTM3U');
  m3u8Buffer.writeln('#EXT-X-VERSION:3');
  m3u8Buffer.writeln('#EXT-X-MEDIA-SEQUENCE:0');

  // write key
  final key = m3u8.key;
  if (key != null) {
    m3u8Buffer.writeln(key.resolveMetaText());
  }

  // write ts
  for (var i = 0; i < m3u8.tsList.length; i++) {
    final ts = m3u8.tsList[i];
    final tsName = '$i.ts';
    m3u8Buffer.writeln(ts.metaText);
    m3u8Buffer.writeln(tsName);
  }

  // write end
  m3u8Buffer.writeln('#EXT-X-ENDLIST');

  // write m3u8 file
  final m3u8File = File(m3u8FilePath);
  await m3u8File.create(recursive: true);
  await m3u8File.writeAsString(m3u8Buffer.toString());

  String ffmpegCmd =
      'ffmpeg -protocol_whitelist "$supportedProtocol" -i $m3u8FilePath -c copy $outputMediaPath';

  // run cmd
  final result = await Process.start('sh', ['-c', ffmpegCmd]);

  result.stdout.transform(utf8.decoder).listen((event) {
    _log(event);
  });

  final totalTsLength = m3u8.tsList.length;

  var time = 0;
  void showMergeProgress(String event) {
    time++;

    if (time % 20 != 0) {
      return;
    }

    // Example: Opening 'crypto:download/1.ts' for reading
    final regex = RegExp('Opening \'(.*)\' for reading');
    final match = regex.firstMatch(event);
    if (match != null) {
      final nameInfo = match.group(1)!;

      if (!nameInfo.endsWith('.ts')) {
        return;
      }

      final tsName = nameInfo.split('/').last;
      final noExtName = tsName.split('.').first;

      final index = noExtName.toInt();
      final mergeProgress = index / totalTsLength;
      final progressText = (mergeProgress * 100).toStringAsFixed(2);
      _log('Merge progress: $progressText%');
    }
  }

  result.stderr.transform(utf8.decoder).listen((event) {
    _verbose(event);
    showMergeProgress(event);
  });

  final exitCode = await result.exitCode;
  _log('exitCode: $exitCode');

  if (exitCode == 0) {
    _log('Merge success');

    if (removeTemp) {
      final dir = Directory(outputPath);
      await dir.delete(recursive: true);
      _log('Remove temp path: $outputPath');
    }

    _log('Output: $outputMediaPath');
  } else {
    _log('Merge failed');
  }
}

class M3u8CommandRunner extends CommandRunner<void> {
  @override
  ArgParser argParser = ArgParser()
    ..addOption('url', abbr: 'u', help: 'm3u8 url')
    ..addOption('output', abbr: 'o', help: 'output file name (not have ext)')
    ..addOption(
      'protocol',
      abbr: 'p',
      defaultsTo: 'file,crypto,data,http,tcp,https,tls',
      help: 'supported protocol (for ffmpeg merge)',
    )
    ..addOption('ext', help: 'output file ext.', defaultsTo: 'mp4')
    ..addOption(
      'threads',
      abbr: 't',
      defaultsTo: '20',
      help: 'download threads',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      defaultsTo: false,
      help: 'show verbose log',
    )
    ..addFlag(
      'remove-temp',
      abbr: 'r',
      defaultsTo: true,
      help: 'remove temp file after merge',
    );

  M3u8CommandRunner(String executableName, String description)
      : super(executableName, description);

  @override
  String get usage => '${super.usage}\n\n'
      'Example: m3u8 -u http://example.com/index.m3u8 -o download';

  @override
  Future<void> runCommand(ArgResults topLevelResults) async {
    final stopwatch = Stopwatch();
    stopwatch.start();
    final result = topLevelResults;

    if (result['help'] as bool) {
      _log(usage);
      return;
    }

    verbose = result['verbose'] as bool;

    final url = result['url'] as String?;
    var outputPath = result['output'] as String?;

    if (url == null) {
      _log('url is null, exit');
      return;
    }

    if (!url.startsWith('http')) {
      _log('url is not start with http, exit');
      return;
    }

    threads = int.parse(result['threads'] as String);

    final protocol = result['protocol'] as String?;
    if (protocol != null) {
      supportedProtocol = protocol;
    }

    // check ffmpeg installed
    final ffmpegResult = await Process.start('bash', ['-c', 'ffmpeg -version']);
    if (await ffmpegResult.exitCode != 0) {
      _log('ffmpeg not installed, exit');
      return;
    }

    final ext = result['ext'] as String? ?? 'mp4';

    removeTemp = result['remove-temp'] as bool;

    outputPath ??= 'download';

    outputPath = getNotRepeatPath(outputPath);

    final outputMediaPath = '$outputPath.$ext';

    _log('Prepared to download: $url');
    _log('Output outputMediaFile: $outputMediaPath');
    _log('Output temp path: $outputPath');

    final m3u8 = await M3u8.from(url);

    // print('m3u8: $m3u8');
    _log('total ts count: ${m3u8.tsList.length}');
    if (m3u8.key != null) {
      _verbose('key: ${m3u8.key}');
    }

    stopwatch.stop();
    _runtime.prepare = stopwatch.elapsedMilliseconds;
    stopwatch.reset();
    stopwatch.start();

    await downloadM3u8(m3u8, outputPath, outputMediaPath);
    stopwatch.stop();
    _runtime.download = stopwatch.elapsedMilliseconds;
    stopwatch.reset();
    stopwatch.start();
    await mergeTs(m3u8, outputPath, outputMediaPath);
    _runtime.merge = stopwatch.elapsedMilliseconds;
    stopwatch.stop();

    _httpClient.close();
  }
}
