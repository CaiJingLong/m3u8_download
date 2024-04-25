class Config {
  static String supportedProtocol = 'file,crypto,data,http,tcp,https,tls';
  static bool removeTemp = true;
  static int threads = 20;
  static bool verbose = false;
  static bool useIsolate = false;
  static int retryCount = 5;
}
