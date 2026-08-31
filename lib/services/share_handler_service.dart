import 'dart:async';

/// Share target mode selected by the user in the Android share sheet
enum ShareMode {
  download,
  music,
}

/// Structured share intent payload
class SharedPayload {
  final String url;
  final ShareMode mode;

  const SharedPayload({
    required this.url,
    this.mode = ShareMode.download,
  });

  factory SharedPayload.fromMap(Map<Object?, Object?> map) {
    final rawUrl = (map['url'] as String?) ?? '';
    final rawMode = (map['mode'] as String?) ?? 'download';
    return SharedPayload(
      url: rawUrl,
      mode: rawMode == 'music' ? ShareMode.music : ShareMode.download,
    );
  }
}

/// Singleton service that buffers incoming shared URLs and delivers them
/// to active listeners (HomeScreen or MusicRecognizer).
class ShareHandlerService {
  ShareHandlerService._();
  static final ShareHandlerService instance = ShareHandlerService._();

  final StreamController<SharedPayload> _controller =
      StreamController<SharedPayload>.broadcast();
  SharedPayload? _pending;

  /// Stream of incoming shared payloads.
  Stream<SharedPayload> get sharedPayloadStream => _controller.stream;

  /// Backwards-compatible stream of incoming URLs.
  Stream<String> get sharedUrlStream =>
      _controller.stream.map((p) => p.url);

  /// Push a new shared payload.
  void pushPayload(SharedPayload payload) {
    if (payload.url.trim().isEmpty) return;
    _pending = payload;
    _controller.add(payload);
  }

  /// Push a raw URL (defaults to download mode).
  void push(String url, {ShareMode mode = ShareMode.download}) {
    if (url.trim().isEmpty) return;
    pushPayload(SharedPayload(url: url, mode: mode));
  }

  /// Return and clear the pending payload (used on cold start).
  SharedPayload? consumePendingPayload() {
    final payload = _pending;
    _pending = null;
    return payload;
  }

  /// Backwards-compatible cold-start pending URL getter.
  String? consumePending() {
    return consumePendingPayload()?.url;
  }

  void dispose() {
    _controller.close();
  }
}
