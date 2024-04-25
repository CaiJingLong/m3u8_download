class StringUtils {
  static String formatSize(int size) {
    if (size < 1024) {
      return '$size B';
    } else if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(2)} KB';
    } else if (size < 1024 * 1024 * 1024) {
      return '${(size / 1024 / 1024).toStringAsFixed(2)} MB';
    } else {
      return '${(size / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
    }
  }
}
