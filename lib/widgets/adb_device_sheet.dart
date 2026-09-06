import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../models/quick_command.dart';
import '../providers/quick_command_provider.dart';

class AdbDeviceSheet extends StatefulWidget {
  const AdbDeviceSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AntigravityTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const AdbDeviceSheet(),
    );
  }

  @override
  State<AdbDeviceSheet> createState() => _AdbDeviceSheetState();
}

class _AdbDeviceSheetState extends State<AdbDeviceSheet> {
  final TextEditingController _targetController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<QuickCommandProvider>();
      provider.refreshAdbDevices();
      if (provider.detectedClientIp != null && provider.detectedClientIp != 'unknown') {
        _targetController.text = '${provider.detectedClientIp}:5555';
      }
    });
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<QuickCommandProvider>();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AntigravityTheme.googlePurple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.install_mobile_rounded, color: AntigravityTheme.googlePurple, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WIRELESS DEBUG & ADB DEVICES',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: AntigravityTheme.textSecondary),
                      ),
                      Text(
                        'Target device for APK wireless installation',
                        style: TextStyle(fontSize: 11, color: AntigravityTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: provider.isLoadingDevices
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AntigravityTheme.googlePurple),
                        )
                      : const Icon(Icons.refresh_rounded, size: 20, color: AntigravityTheme.googlePurple),
                  tooltip: 'Rescan ADB Devices',
                  onPressed: provider.isLoadingDevices ? null : () => provider.refreshAdbDevices(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Connected Devices List
            const Text(
              'AVAILABLE DEVICES',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AntigravityTheme.textSecondary),
            ),
            const SizedBox(height: 8),

            if (provider.adbDevices.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AntigravityTheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AntigravityTheme.borderSubtle),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.phonelink_erase_rounded, size: 20, color: AntigravityTheme.googleAmber),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'No ADB devices connected yet.',
                            style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            provider.detectedClientIp != null
                                ? 'Use "Connect to My Phone" below to pair with ${provider.detectedClientIp}:5555'
                                : 'Enable Wireless Debugging in Developer Options on your phone.',
                            style: const TextStyle(fontSize: 10.5, color: AntigravityTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              ...provider.adbDevices.map((AdbDevice dev) {
                final isSelected = provider.selectedAdbDevice?.serial == dev.serial;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: isSelected
                        ? AntigravityTheme.googlePurple.withValues(alpha: 0.12)
                        : AntigravityTheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? AntigravityTheme.googlePurple : AntigravityTheme.borderSubtle,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        leading: Icon(
                          dev.isWireless ? Icons.wifi_tethering : Icons.usb_rounded,
                          color: dev.isConnected ? AntigravityTheme.googleGreen : AntigravityTheme.textMuted,
                          size: 20,
                        ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            dev.displayName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              color: isSelected ? Colors.white : AntigravityTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: dev.isConnected
                                ? AntigravityTheme.googleGreen.withValues(alpha: 0.15)
                                : AntigravityTheme.googleRed.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            dev.status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: dev.isConnected ? AntigravityTheme.googleGreen : AntigravityTheme.googleRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      '${dev.serial}${dev.product.isNotEmpty ? " • ${dev.product}" : ""}',
                      style: const TextStyle(fontSize: 10, color: AntigravityTheme.textMuted, fontFamily: 'monospace'),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (dev.isWireless)
                          IconButton(
                            icon: const Icon(Icons.link_off_rounded, size: 18, color: AntigravityTheme.googleRed),
                            tooltip: 'Disconnect',
                            onPressed: () => provider.disconnectAdbDevice(dev.serial),
                          ),
                        if (isSelected)
                          const Icon(Icons.check_circle_rounded, size: 20, color: AntigravityTheme.googlePurple)
                        else
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => provider.selectAdbDevice(dev),
                            child: const Text('Select', style: TextStyle(fontSize: 11)),
                          ),
                      ],
                    ),
                    onTap: () => provider.selectAdbDevice(dev),
                  ),
                ),
              ),
            );
          }),

            const SizedBox(height: 16),
            const Text(
              'WIRELESS CONNECT (IP : PORT)',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AntigravityTheme.textSecondary),
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _targetController,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      hintText: '192.168.1.50:5555',
                      prefixIcon: Icon(Icons.wifi_rounded, size: 16, color: AntigravityTheme.googleBlue),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AntigravityTheme.googlePurple,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  icon: const Icon(Icons.link_rounded, size: 16),
                  label: const Text('Connect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    final target = _targetController.text.trim();
                    if (target.isNotEmpty) {
                      provider.connectAdbDevice(target);
                    }
                  },
                ),
              ],
            ),

            if (provider.detectedClientIp != null && provider.detectedClientIp != 'unknown') ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    _targetController.text = '${provider.detectedClientIp}:5555';
                  });
                },
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 13, color: AntigravityTheme.googleBlue),
                    const SizedBox(width: 6),
                    Text(
                      'Auto-fill my phone IP: ${provider.detectedClientIp}:5555',
                      style: const TextStyle(fontSize: 11, color: AntigravityTheme.googleBlue, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
