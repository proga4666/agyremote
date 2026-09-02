import 'package:flutter/material.dart';
import '../core/network/bridge_client.dart';
import '../core/network/discovery_service.dart';

class ConnectionProvider extends ChangeNotifier {
  final BridgeClient bridge;
  final DiscoveryService discovery = DiscoveryService();

  String _hostAddress = '192.168.0.109';
  int _port = 7800;
  bool _useSsl = false;
  String _statusMessage = 'Searching for PC on Wi-Fi...';
  List<DiscoveredHost> discoveredHosts = [];

  ConnectionProvider({required this.bridge}) {
    bridge.statusStream.listen((status) {
      _updateStatusMessage(status);
      notifyListeners();
    });

    bridge.events.listen((event) {
      if (event['event'] == 'status_notice') {
        _statusMessage = event['message'] ?? _statusMessage;
        notifyListeners();
      }
    });

    // Start Auto-Discovery immediately
    _initAutoDiscovery();
  }

  void _initAutoDiscovery() {
    discovery.hostsStream.listen((hosts) {
      discoveredHosts = hosts;
      notifyListeners();
    });

    discovery.startDiscovery(onFound: (host) {
      debugPrint('[AutoDiscovery] Found PC: ${host.hostName} at ${host.ipAddress}:${host.port}');
      // Auto-connect if disconnected or connecting to old IP
      if (!isConnected || _hostAddress != host.ipAddress) {
        _hostAddress = host.ipAddress;
        _port = host.port;
        _statusMessage = 'Auto-detected ${host.hostName} (${host.ipAddress}). Connecting...';
        notifyListeners();
        reconnect();
      }
    });
  }

  String get hostAddress => _hostAddress;
  int get port => _port;
  bool get useSsl => _useSsl;
  String get statusMessage => _statusMessage;
  BridgeStatus get status => bridge.status;
  bool get isConnected => bridge.status == BridgeStatus.connected;
  bool get isMockMode => bridge.isMockMode;
  bool get isScanning => discovery.isSearching;
  String get fullUrl => '${_useSsl ? "wss" : "ws"}://$_hostAddress:$_port/ws';

  void _updateStatusMessage(BridgeStatus s) {
    switch (s) {
      case BridgeStatus.connected:
        discovery.stopDiscovery();
        _statusMessage = bridge.isMockMode
            ? 'Connected (Demo Simulator)'
            : 'Connected to Workstation ($_hostAddress)';
        break;
      case BridgeStatus.connecting:
        _statusMessage = 'Connecting to $fullUrl...';
        break;
      case BridgeStatus.error:
        _statusMessage = 'Searching for PC daemon on local Wi-Fi...';
        break;
      case BridgeStatus.disconnected:
        _statusMessage = 'Disconnected';
        break;
    }
  }

  void scanForHosts() {
    discovery.startDiscovery();
    notifyListeners();
  }

  void connectToDiscoveredHost(DiscoveredHost host) {
    _hostAddress = host.ipAddress;
    _port = host.port;
    _useSsl = false;
    reconnect();
    notifyListeners();
  }

  void updateHostConfig({
    required String host,
    required int port,
    bool useSsl = false,
  }) {
    _hostAddress = host.trim();
    _port = port;
    _useSsl = useSsl;
    reconnect();
    notifyListeners();
  }

  void reconnect() {
    bridge.connect(fullUrl, forceMock: false);
    notifyListeners();
  }

  void enableDemoMode() {
    bridge.connect(fullUrl, forceMock: true);
    notifyListeners();
  }

  void disconnect() {
    bridge.disconnect(intentional: true);
    notifyListeners();
  }

  @override
  void dispose() {
    discovery.stopDiscovery();
    super.dispose();
  }
}
