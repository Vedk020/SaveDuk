import 'dart:async';

/// Singleton service that buffers incoming shared URLs and delivers them
/// to the first active listener (typically HomeScreen).
class ShareHandlerService {
  ShareHandlerService._();
  static final ShareHandlerService instance = ShareHandlerService._();

  final StreamController<String> _controller = StreamController<String>.broadcast();
  String? _pending;

  /// Stream of incoming shared URLs.
  Stream<String> get sharedUrlStream => _controller.stream;

  /// Push a new shared URL. If no listener is active yet, it is
  /// buffered and delivered when [consumePending] is called.
  void push(String url) {
    _pending = url;
    _controller.add(url);
  }

  /// Return and clear the pending URL (used on cold start).
  String? consumePending() {
    final url = _pending;
    _pending = null;
    return url;
  }

  void dispose() {
    _controller.close();
  }
}
