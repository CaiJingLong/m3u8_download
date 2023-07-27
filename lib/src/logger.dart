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
}

final logger = M3u8Logger();
