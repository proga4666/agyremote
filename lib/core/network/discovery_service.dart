import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class DiscoveredHost {
  final String hostName;
  final String ipAddress;
  final int port;
  final DateTime lastSeen;

  DiscoveredHost({
    required this.hostName,
    required this.ipAddress,
    required this.port,
    required this.lastSeen,
  });

  String get wsUrl => 'ws://$ipAddress:$port/ws';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredHost &&
          runtimeType == other.runtimeType &&
          ipAddress == other.ipAddress &&
          port == other.port;

  @override
  int get hashCode => ipAddress.hashCode ^ port.hashCode;
}

class DiscoveryService {
  static const int discoveryPort = 7801;
  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  bool _isSearching = false;
  int _pingCount = 0;

  final _hostController = StreamController<List<DiscoveredHost>>.broadcast();
  final Map<String, DiscoveredHost> _discoveredMap = {};

  Stream<List<DiscoveredHost>> get hostsStream => _hostController.stream;
  List<DiscoveredHost> get hosts => _discoveredMap.values.toList();
  bool get isSearching => _isSearching;

  void Function(DiscoveredHost host)? onHostDiscovered;

  Future<void> startDiscovery({void Function(DiscoveredHost host)? onFound}) async {
    if (onFound != null) onHostDiscovered = onFound;
    if (_isSearching) return;
    _isSearching = true;
    _pingCount = 0;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      _socket!.broadcastEnabled = true;

      _socket!.listen(
        (RawSocketEvent event) {
          if (event == RawSocketEvent.read && _socket != null) {
            try {
              final datagram = _socket!.receive();
              if (datagram != null) {
                _handleIncomingPacket(datagram);
              }
            } catch (e) {
              debugPrint('[Discovery] Socket read error: $e');
            }
          }
        },
        onError: (e) {
          debugPrint('[Discovery] Socket stream error: $e');
        },
      );

      // Send initial discovery ping immediately
      _sendDiscoveryPing();

      // Repeat ping up to 5 times (every 2 seconds) then relax
      _broadcastTimer?.cancel();
      _broadcastTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        _pingCount++;
        _sendDiscoveryPing();
        if (_pingCount >= 5 && _discoveredMap.isNotEmpty) {
          // Stop aggressive pinging once host is found
          timer.cancel();
          _broadcastTimer = null;
        }
      });
    } catch (e) {
      debugPrint('[Discovery] Error starting UDP discovery: $e');
    }
  }

  void _sendDiscoveryPing() async {
    if (_socket == null || !_isSearching) return;
    final msg = utf8.encode('ANTIGRAVITY_DISCOVER');

    // 1. Try global broadcast
    try {
      _socket?.send(
        msg,
        InternetAddress('255.255.255.255'),
        discoveryPort,
      );
    } catch (_) {}

    // 2. Also try subnet broadcast for local network interfaces
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
            try {
              _socket?.send(
                msg,
                InternetAddress(subnetBroadcast),
                discoveryPort,
              );
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  void _handleIncomingPacket(Datagram datagram) {
    try {
      final text = utf8.decode(datagram.data).trim();
      final senderIp = datagram.address.address;

      if (text.startsWith('{') && text.endsWith('}')) {
        final decoded = jsonDecode(text) as Map<String, dynamic>;
        if (decoded['service'] == 'antigravity_daemon') {
          final hostName = decoded['host_name']?.toString() ?? 'Workstation';
          final port = (decoded['port'] as int?) ?? 7800;

          final host = DiscoveredHost(
            hostName: hostName,
            ipAddress: senderIp,
            port: port,
            lastSeen: DateTime.now(),
          );

          final key = '$senderIp:$port';
          final isNew = !_discoveredMap.containsKey(key);
          _discoveredMap[key] = host;

          _hostController.add(_discoveredMap.values.toList());

          if (isNew && onHostDiscovered != null) {
            onHostDiscovered!(host);
          }
        }
      }
    } catch (e) {
      debugPrint('[Discovery] Packet decode error: $e');
    }
  }

  void stopDiscovery() {
    _isSearching = false;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}
