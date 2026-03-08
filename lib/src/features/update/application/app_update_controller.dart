import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update_service.dart';

class AppUpdateController extends ChangeNotifier {
  AppUpdateController({
    required AppUpdateService service,
  }) : _service = service;

  final AppUpdateService _service;
  AppUpdateInfo? _latest;
  String? _error;
  bool _isChecking = false;
  bool _isLaunching = false;

  AppUpdateInfo? get latest => _latest;
  String? get error => _error;
  bool get isChecking => _isChecking;
  bool get isLaunching => _isLaunching;

  Future<void> checkForUpdates() async {
    if (_isChecking) {
      return;
    }
    _isChecking = true;
    _error = null;
    notifyListeners();

    try {
      _latest = await _service.checkForUpdate();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }

  Future<bool> openUpdateUrl() async {
    final latest = _latest;
    if (latest == null) {
      return false;
    }
    final url = latest.downloadUrl.isNotEmpty ? latest.downloadUrl : latest.releaseUrl;
    if (url.isEmpty) {
      return false;
    }

    _isLaunching = true;
    notifyListeners();
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } finally {
      _isLaunching = false;
      notifyListeners();
    }
  }
}
