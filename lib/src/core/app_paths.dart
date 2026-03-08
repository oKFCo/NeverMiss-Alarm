import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String> resolveAppStorageBasePath() async {
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return '$appData\\nevermiss_alarm';
    }
  }
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;
  return '$home${Platform.pathSeparator}.nevermiss_alarm';
}
