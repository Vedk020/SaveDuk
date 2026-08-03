import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';

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
  final GlobalKey<AppShellState> _appShellKey = GlobalKey();
  static const MethodChannel _shareChannel = MethodChannel('saveduk/share');

  @override
  void initState() {
    super.initState();
    _shareChannel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText') {
        _processSharedText(call.arguments as String?);
      }
    });
    _loadInitialSharedText();
  }

  Future<void> _loadInitialSharedText() async {
    try {
      _processSharedText(
        await _shareChannel.invokeMethod<String>('takeSharedText'),
      );
    } on MissingPluginException {
      // Share receiving is currently implemented for Android only.
    }
  }

  void _processSharedText(String? text) {
    if (text == null || text.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _appShellKey.currentState?.handleSharedUrl(text);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SaveDukApp(key: _appShellKey, initialSharedUrl: null);
  }
}
