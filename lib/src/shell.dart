import 'dart:io';

Future<bool> isProgramInstalled(String programName) async {
  if (Platform.isWindows) {
    try {
      ProcessResult result = await Process.run(
        'where',
        [programName],
        runInShell: true,
      );
      print(result.stdout);
      if (result.exitCode == 0) {
        return true;
      }
    } catch (e) {
      // Error occurred, program is not installed or not in the PATH
      return false;
    }
    return false;
  } else {
    try {
      ProcessResult result = await Process.run('which', [programName]);
      if (result.exitCode == 0) {
        return true;
      }
    } catch (e) {
      // Error occurred, program is not installed or not in the PATH
      return false;
    }
    return false;
  }
}
