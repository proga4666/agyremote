import 'package:flutter/material.dart';
import '../core/network/bridge_client.dart';
import '../core/network/discovery_service.dart';
import '../models/daemon_status.dart';

class ConnectionProvider extends ChangeNotifier {
  final BridgeClient bridge;
  final DiscoveryService discovery = DiscoveryService();

  String _hostAddress = '192.168.0.109';
  int _port = 7800;
  bool _useSsl = false;
  String _statusMessage = 'Searching for PC on Wi-Fi...';
  List<DiscoveredHost> discoveredHosts = [];

  DaemonStatusInfo? daemonStatus;
  List<DiagnosticCheck> diagnosticResults = [];
  bool isRunningDiagnostics = false;
  bool isRestarting = false;
  bool isAuthRefreshing = false;
  String? authNotice;

  ConnectionProvider({required this.bridge}) {
    bridge.statusStream.listen((status) {
      _updateStatusMessage(status);
      if (status == BridgeStatus.connected) {
        fetchDaemonStatus();
      }
      notifyListeners();
    });

    bridge.events.listen(_handleDaemonEvents);

    // Start Auto-Discovery immediately
    _initAutoDiscovery();
  }

  void _handleDaemonEvents(Map<String, dynamic> event) {
    switch (event['event']) {
      case 'status_notice':
        _statusMessage = event['message'] ?? _statusMessage;
        notifyListeners();
        break;

      case 'daemon_status':
        isRestarting = false;
        daemonStatus = DaemonStatusInfo.fromJson(Map<String, dynamic>.from(event));
        notifyListeners();
        break;

      case 'daemon_restarting':
        isRestarting = true;
        _statusMessage = event['message']?.toString() ?? 'Daemon restarting...';
        notifyListeners();
        break;

      case 'config_updated':
        authNotice = event['message']?.toString();
        notifyListeners();
        break;

      case 'auth_status':
        isAuthRefreshing = false;
        authNotice = event['message']?.toString();
        if (daemonStatus != null) {
          final isAuth = event['is_authenticated'] == true;
          final account = event['auth_account']?.toString() ?? daemonStatus!.authAccount;
          daemonStatus = DaemonStatusInfo(
            status: daemonStatus!.status,
            uptimeSeconds: daemonStatus!.uptimeSeconds,
            pid: daemonStatus!.pid,
            platform: daemonStatus!.platform,
            instanceType: daemonStatus!.instanceType,
            cliHostname: daemonStatus!.cliHostname,
            desktopHostname: daemonStatus!.desktopHostname,
            updateInterval: daemonStatus!.updateInterval,
            hasCliNameOverride: daemonStatus!.hasCliNameOverride,
            configFilePath: daemonStatus!.configFilePath,
            authAccount: account,
            isAuthenticated: isAuth,
            recentLogs: daemonStatus!.recentLogs,
            activePort: daemonStatus!.activePort,
            discoveryPort: daemonStatus!.discoveryPort,
          );
        }
        notifyListeners();
        break;

      case 'diagnostics_result':
        isRunningDiagnostics = false;
        final rawChecks = event['checks'] as List<dynamic>? ?? [];
        diagnosticResults = rawChecks
            .map((c) => DiagnosticCheck.fromJson(Map<String, dynamic>.from(c)))
            .toList();
        notifyListeners();
        break;
    }
  }

  void _initAutoDiscovery() {
    discovery.hostsStream.listen((hosts) {
      discoveredHosts = hosts;
      notifyListeners();
    });

    discovery.startDiscovery(onFound: (host) {
      debugPrint('[AutoDiscovery] Found PC: ${host.hostName} at ${host.ipAddress}:${host.port}');
      if (!isConnected || _hostAddress != host.ipAddress) {
        _hostAddress = host.ipAddress;
        _port = host.port;
        _statusMessage = 'Auto-detected ${host.displayTitle} (${host.ipAddress}). Connecting...';
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

  // --- Headless Daemon Service Controls ---
  void fetchDaemonStatus() {
    bridge.send('get_daemon_status', {});
  }

  void restartDaemon() {
    isRestarting = true;
    notifyListeners();
    bridge.send('restart_daemon', {});
  }

  void updateHostnames({
    String? cliHostname,
    String? desktopHostname,
    String? updateInterval,
  }) {
    final payload = <String, dynamic>{};
    if (cliHostname != null) {
      payload['cli_remote_control_hostname'] = cliHostname.trim();
    }
    if (desktopHostname != null) {
      payload['remote_control_hostname'] = desktopHostname.trim();
    }
    if (updateInterval != null) {
      payload['update_interval'] = updateInterval;
    }
    bridge.send('update_config', payload);
  }

  void refreshAuth() {
    isAuthRefreshing = true;
    notifyListeners();
    bridge.send('refresh_auth', {});
  }

  void submitAuthCode(String code) {
    bridge.send('submit_auth_code', {'code': code.trim()});
  }

  void runDiagnostics() {
    isRunningDiagnostics = true;
    diagnosticResults.clear();
    notifyListeners();
    bridge.send('run_diagnostics', {});
  }

  @override
  void dispose() {
    discovery.stopDiscovery();
    super.dispose();
  }
}
