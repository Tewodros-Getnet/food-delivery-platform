import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../../../core/constants/api_constants.dart';
import '../../../core/storage/secure_storage.dart';

final socketServiceProvider = Provider<SocketService>((ref) {
  final svc = SocketService(ref.read(secureStorageProvider));
  // Auto-connect when provider is created
  svc.connect();
  return svc;
});

class SocketService {
  final SecureStorageService _storage;
  io.Socket? _socket;
  final List<_PendingListener> _pendingListeners = [];

  SocketService(this._storage);

  Future<void> connect() async {
    final token = await _storage.getJwt();
    if (token == null) return;

    _socket = io.io(
      ApiConstants.wsUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .build(),
    );

    // Register any listeners that were added before connect() completed
    for (final p in _pendingListeners) {
      _socket!.on(p.event, p.handler);
    }
    _pendingListeners.clear();
  }

  void on(String event, Function(dynamic) handler) {
    if (_socket != null) {
      _socket!.on(event, handler);
    } else {
      // Queue until socket is ready
      _pendingListeners.add(_PendingListener(event, handler));
    }
  }

  void off(String event) {
    _socket?.off(event);
    _pendingListeners.removeWhere((p) => p.event == event);
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }

  bool get isConnected => _socket?.connected ?? false;
}

class _PendingListener {
  final String event;
  final Function(dynamic) handler;
  _PendingListener(this.event, this.handler);
}
