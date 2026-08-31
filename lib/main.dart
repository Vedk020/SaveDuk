import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'services/share_handler_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      if (call.method == 'sharedText') {
        final text = call.arguments as String?;
        if (text != null && text.isNotEmpty) {
          ShareHandlerService.instance.push(text);
        }
      }
    });
    _loadInitialSharedText();
  }

  Future<void> _loadInitialSharedText() async {
    try {
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
