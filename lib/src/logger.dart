import 'dart:io';

import 'package:m3u8_download/src/config.dart';

class M3u8Logger {
  M3u8Logger();

  void log(String message) {
    print(message);
  }

  void verbose(String message) {
    if (Config.verbose) {
      print(message);
    }
  }

  void write(String message) {
    if (message.startsWith('\r')) {
      message = '$message ';
    }
    stdout.write(message);
  }

  void error(String message) {
    stderr.writeln(message);
  }
}

final logger = M3u8Logger();
