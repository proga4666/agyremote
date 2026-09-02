import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/network/bridge_client.dart';
import '../core/network/discovery_service.dart';
import '../core/theme/app_theme.dart';
import '../providers/connection_provider.dart';

class ConnectionDialog extends StatefulWidget {
  const ConnectionDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const ConnectionDialog(),
    );
  }

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  bool _useSsl = false;

  @override
  void initState() {
    super.initState();
    final conn = context.read<ConnectionProvider>();
    _hostController = TextEditingController(text: conn.hostAddress);
    _portController = TextEditingController(text: conn.port.toString());
    _useSsl = conn.useSsl;
    conn.scanForHosts();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionProvider>();

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AntigravityTheme.googleBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.wifi_find_rounded, color: AntigravityTheme.googleBlue, size: 20),
          ),
          const SizedBox(width: 10),
          const Text('Daemon Connection', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _getStatusBg(conn.status),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _getStatusBorder(conn.status)),
              ),
              child: Row(
                children: [
                  Icon(_getStatusIcon(conn.status), color: _getStatusColor(conn.status), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      conn.statusMessage,
                      style: TextStyle(
                        fontSize: 12,
                        color: _getStatusColor(conn.status),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Discovered PC Section
            Row(
              children: [
                const Icon(Icons.radar_rounded, size: 16, color: AntigravityTheme.googleGreen),
                const SizedBox(width: 6),
                const Text(
                  'Auto-Detected on Wi-Fi:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AntigravityTheme.googleGreen),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => conn.scanForHosts(),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.refresh, size: 16, color: AntigravityTheme.googleBlue),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            if (conn.discoveredHosts.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AntigravityTheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AntigravityTheme.borderSubtle),
                ),
                child: Row(
                  children: const [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AntigravityTheme.googleBlue),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Broadcasting for host PC on local Wi-Fi...',
                        style: TextStyle(fontSize: 11, color: AntigravityTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...conn.discoveredHosts.map((DiscoveredHost h) {
                final isCurrent = conn.hostAddress == h.ipAddress;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? AntigravityTheme.googleGreen.withValues(alpha: 0.12)
                        : AntigravityTheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCurrent ? AntigravityTheme.googleGreen : AntigravityTheme.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.computer,
                        color: isCurrent ? AntigravityTheme.googleGreen : AntigravityTheme.googleBlue,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              h.hostName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              '${h.ipAddress}:${h.port}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AntigravityTheme.textSecondary,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isCurrent ? AntigravityTheme.surfaceContainerHigh : AntigravityTheme.googleGreen,
                          foregroundColor: isCurrent ? Colors.white : Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          conn.connectToDiscoveredHost(h);
                          Navigator.pop(context);
                        },
                        child: Text(
                          isCurrent ? 'Active' : 'Connect',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                );
              }),

            const SizedBox(height: 16),
            const Divider(color: AntigravityTheme.borderSubtle),
            const SizedBox(height: 8),

            const Text(
              'Manual Host Override:',
              style: TextStyle(fontSize: 11, color: AntigravityTheme.textSecondary, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'Host IP / Hostname',
                hintText: 'e.g. 192.168.0.109',
                prefixIcon: Icon(Icons.computer_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'WebSocket Port',
                hintText: '7800',
                prefixIcon: Icon(Icons.numbers_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Use Secure WebSocket (WSS)', style: TextStyle(fontSize: 13)),
              value: _useSsl,
              activeThumbColor: AntigravityTheme.googleBlue,
              onChanged: (val) => setState(() => _useSsl = val),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: AntigravityTheme.textSecondary)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AntigravityTheme.googleBlue,
            foregroundColor: Colors.black,
          ),
          icon: const Icon(Icons.sync_rounded, size: 16),
          label: const Text('Connect Manual IP', style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () {
            final host = _hostController.text.trim();
            final port = int.tryParse(_portController.text.trim()) ?? 7800;
            if (host.isNotEmpty) {
              conn.updateHostConfig(host: host, port: port, useSsl: _useSsl);
              Navigator.pop(context);
            }
          },
        ),
      ],
    );
  }

  Color _getStatusColor(BridgeStatus status) {
    switch (status) {
      case BridgeStatus.connected:
        return AntigravityTheme.googleGreen;
      case BridgeStatus.connecting:
        return AntigravityTheme.googleAmber;
      case BridgeStatus.error:
        return AntigravityTheme.googleRed;
      case BridgeStatus.disconnected:
        return AntigravityTheme.textSecondary;
    }
  }

  Color _getStatusBg(BridgeStatus status) {
    return _getStatusColor(status).withValues(alpha: 0.12);
  }

  Color _getStatusBorder(BridgeStatus status) {
    return _getStatusColor(status).withValues(alpha: 0.3);
  }

  IconData _getStatusIcon(BridgeStatus status) {
    switch (status) {
      case BridgeStatus.connected:
        return Icons.check_circle_outline;
      case BridgeStatus.connecting:
        return Icons.hourglass_top_rounded;
      case BridgeStatus.error:
        return Icons.error_outline;
      case BridgeStatus.disconnected:
        return Icons.cloud_off_outlined;
    }
  }
}
