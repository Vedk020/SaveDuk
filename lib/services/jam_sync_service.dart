import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/music_track.dart';
import 'music_player_service.dart';

enum JamRole { none, host, guest }

/// Service enabling peer-to-peer synchronized music playback between two or more SaveDuk apps
/// over local Wi-Fi or Mobile Hotspot using a 6-digit session PIN.
class JamSyncService {
  JamSyncService._();
  static final JamSyncService instance = JamSyncService._();

  JamRole _role = JamRole.none;
  JamRole get role => _role;

  String? _sessionPin;
  String? get sessionPin => _sessionPin;

  String? _localIp;
  String? get localIp => _localIp;

  HttpServer? _server;
  final List<WebSocket> _clients = [];
  WebSocket? _clientSocket;

  final ValueNotifier<int> connectedGuestsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String?> statusMessageNotifier = ValueNotifier<String?>(null);

  StreamSubscription? _playerStateSub;
  StreamSubscription? _positionSub;

  /// Generate a random 6-digit PIN
  String _generatePin() {
    final rand = Random();
    return (100000 + rand.nextInt(900000)).toString();
  }

  /// Get device's local IPv4 address
  Future<String?> getDeviceIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168.') ||
              addr.address.startsWith('10.') ||
              addr.address.startsWith('172.')) {
            return addr.address;
          }
        }
      }
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (e) {
      debugPrint('[JamSyncService] IP discovery error: $e');
    }
    return '127.0.0.1';
  }

  /// Start Host mode: creates local WebSocket server
  Future<bool> startHosting() async {
    await stopSession();

    try {
      _localIp = await getDeviceIp();
      _sessionPin = _generatePin();

      _server = await HttpServer.bind(InternetAddress.anyIPv4, 8088);
      _role = JamRole.host;
      isConnectedNotifier.value = true;
      statusMessageNotifier.value = 'Hosting on $_localIp (PIN: $_sessionPin)';

      _server!.listen((HttpRequest request) async {
        if (request.uri.path == '/ws') {
          final queryPin = request.uri.queryParameters['pin'];
          if (queryPin != _sessionPin) {
            request.response.statusCode = HttpStatus.unauthorized;
            request.response.close();
            return;
          }

          final socket = await WebSocketTransformer.upgrade(request);
          _clients.add(socket);
          connectedGuestsNotifier.value = _clients.length;

          // Send immediate current playback state to new guest
          _sendStateTo(socket);

          socket.listen(
            (data) => _handleHostIncoming(socket, data),
            onDone: () {
              _clients.remove(socket);
              connectedGuestsNotifier.value = _clients.length;
            },
            onError: (_) {
              _clients.remove(socket);
              connectedGuestsNotifier.value = _clients.length;
            },
          );
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.close();
        }
      });

      // Hook into MusicPlayerService to broadcast play/pause/seek events
      _bindHostListeners();
      return true;
    } catch (e) {
      debugPrint('[JamSyncService] Failed to start host: $e');
      await stopSession();
      return false;
    }
  }

  void _bindHostListeners() {
    final playerService = MusicPlayerService.instance;

    _playerStateSub = playerService.playerStateStream.listen((state) {
      _broadcast({
        'action': 'state_change',
        'isPlaying': state.playing,
        'positionMs': playerService.player.position.inMilliseconds,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    });

    _positionSub = playerService.positionStream.listen((pos) {
      // Periodically sync position
      if (pos.inSeconds % 5 == 0) {
        _broadcast({
          'action': 'sync_pos',
          'positionMs': pos.inMilliseconds,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
  }

  void _sendStateTo(WebSocket socket) {
    final playerService = MusicPlayerService.instance;
    final track = playerService.currentTrack;

    final msg = jsonEncode({
      'action': 'initial_state',
      'track': track?.toMap(),
      'isPlaying': playerService.isPlaying,
      'positionMs': playerService.player.position.inMilliseconds,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    try {
      socket.add(msg);
    } catch (_) {}
  }

  void _broadcast(Map<String, dynamic> data) {
    final msg = jsonEncode(data);
    for (final client in List<WebSocket>.from(_clients)) {
      try {
        client.add(msg);
      } catch (_) {
        _clients.remove(client);
        connectedGuestsNotifier.value = _clients.length;
      }
    }
  }

  void _handleHostIncoming(WebSocket socket, dynamic data) {
    // If guest sends a request (e.g. ping), respond
  }

  /// Join an active Jam hosted by another device
  Future<bool> joinJam({required String hostIp, required String pin}) async {
    await stopSession();

    try {
      final uri = Uri.parse('ws://$hostIp:8088/ws?pin=$pin');
      _clientSocket = await WebSocket.connect(uri.toString()).timeout(const Duration(seconds: 5));

      _role = JamRole.guest;
      _sessionPin = pin;
      _localIp = hostIp;
      isConnectedNotifier.value = true;
      statusMessageNotifier.value = 'Synced with DJ at $hostIp';

      _clientSocket!.listen(
        (data) => _handleGuestIncoming(data),
        onDone: () => stopSession(),
        onError: (_) => stopSession(),
      );

      return true;
    } catch (e) {
      debugPrint('[JamSyncService] Join failed: $e');
      await stopSession();
      return false;
    }
  }

  Future<void> _handleGuestIncoming(dynamic rawData) async {
    try {
      final Map<String, dynamic> data = jsonDecode(rawData.toString());
      final action = data['action'] as String?;
      final playerService = MusicPlayerService.instance;

      if (action == 'initial_state' || action == 'track_change') {
        final trackMap = data['track'] as Map<String, dynamic>?;
        if (trackMap != null) {
          final track = MusicTrack.fromMap(trackMap);
          final isPlaying = data['isPlaying'] == true;
          final posMs = (data['positionMs'] as num?)?.toInt() ?? 0;

          if (playerService.currentTrack?.id != track.id) {
            await playerService.playTrack(track);
            await playerService.seek(Duration(milliseconds: posMs));
            if (!isPlaying) await playerService.pause();
          }
        }
      } else if (action == 'state_change') {
        final isPlaying = data['isPlaying'] == true;
        final posMs = (data['positionMs'] as num?)?.toInt() ?? 0;

        if (isPlaying && !playerService.isPlaying) {
          await playerService.seek(Duration(milliseconds: posMs));
          await playerService.resume();
        } else if (!isPlaying && playerService.isPlaying) {
          await playerService.pause();
        }
      } else if (action == 'sync_pos') {
        final posMs = (data['positionMs'] as num?)?.toInt() ?? 0;
        final currentPos = playerService.player.position.inMilliseconds;
        if ((currentPos - posMs).abs() > 350) {
          await playerService.seek(Duration(milliseconds: posMs));
        }
      }
    } catch (e) {
      debugPrint('[JamSyncService] Guest handle error: $e');
    }
  }

  /// Broadcast track change when Host plays a new track
  void notifyTrackChanged(MusicTrack track) {
    if (_role == JamRole.host) {
      _broadcast({
        'action': 'track_change',
        'track': track.toMap(),
        'isPlaying': true,
        'positionMs': 0,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  /// Stop host or disconnect guest
  Future<void> stopSession() async {
    _playerStateSub?.cancel();
    _positionSub?.cancel();

    for (final client in _clients) {
      try {
        await client.close();
      } catch (_) {}
    }
    _clients.clear();

    try {
      await _clientSocket?.close();
    } catch (_) {}
    _clientSocket = null;

    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;

    _role = JamRole.none;
    _sessionPin = null;
    connectedGuestsNotifier.value = 0;
    isConnectedNotifier.value = false;
    statusMessageNotifier.value = null;
  }
}
