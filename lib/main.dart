import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'services/share_handler_service.dart';

import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.instance.init();
  runApp(const SaveDukBootstrap());
}

class SaveDukBootstrap extends StatefulWidget {
  const SaveDukBootstrap({super.key});

  @override
  State<SaveDukBootstrap> createState() => _SaveDukBootstrapState();
}

class _SaveDukBootstrapState extends State<SaveDukBootstrap> {
  static const MethodChannel _shareChannel = MethodChannel('saveduk/share');

  @override
  void initState() {
    super.initState();
    _shareChannel.setMethodCallHandler((call) async {
      if (call.method == 'sharedPayload' && call.arguments is Map) {
        final map = call.arguments as Map;
        final payload = SharedPayload.fromMap(Map<Object?, Object?>.from(map));
        ShareHandlerService.instance.pushPayload(payload);
      } else if (call.method == 'sharedText') {
        final text = call.arguments as String?;
        if (text != null && text.isNotEmpty) {
          ShareHandlerService.instance.push(text);
        }
      }
    });
    _loadInitialSharedPayload();
  }

  Future<void> _loadInitialSharedPayload() async {
    try {
      final raw = await _shareChannel.invokeMethod<Object?>('takeSharedPayload');
      if (raw is Map) {
        final payload = SharedPayload.fromMap(Map<Object?, Object?>.from(raw));
        ShareHandlerService.instance.pushPayload(payload);
        return;
      }
      final text = await _shareChannel.invokeMethod<String>('takeSharedText');
      if (text != null && text.isNotEmpty) {
        ShareHandlerService.instance.push(text);
      }
    } on MissingPluginException {
      // Share receiving is currently implemented for Android only.
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SaveDukApp();
  }
}
