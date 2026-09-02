import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_theme.dart';
import '../models/approval.dart';

class DiffViewerScreen extends StatelessWidget {
  final CodeDiffArtifact artifact;

  const DiffViewerScreen({super.key, required this.artifact});

  @override
  Widget build(BuildContext context) {
    final lines = artifact.diffContent.split('\n');

    return Scaffold(
      backgroundColor: AntigravityTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              artifact.filePath.split('/').last,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              artifact.filePath,
              style: const TextStyle(
                fontSize: 11,
                color: AntigravityTheme.textSecondary,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 18),
            tooltip: 'Copy Diff',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: artifact.diffContent));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Diff copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Stat summary bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AntigravityTheme.surface,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AntigravityTheme.googleGreen.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '+${artifact.additions}',
                    style: const TextStyle(
                      color: AntigravityTheme.googleGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AntigravityTheme.googleRed.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '-${artifact.deletions}',
                    style: const TextStyle(
                      color: AntigravityTheme.googleRed,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${lines.length} lines modified',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AntigravityTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AntigravityTheme.border),
          // Diff lines
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final line = lines[index];
                return _buildDiffLine(line, index + 1);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffLine(String line, int lineNum) {
    Color bg = Colors.transparent;
    Color textColor = AntigravityTheme.textPrimary;
    Color badgeColor = Colors.transparent;

    if (line.startsWith('+') && !line.startsWith('+++')) {
      bg = AntigravityTheme.googleGreen.withValues(alpha: 0.12);
      textColor = AntigravityTheme.googleGreen;
      badgeColor = AntigravityTheme.googleGreen;
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      bg = AntigravityTheme.googleRed.withValues(alpha: 0.12);
      textColor = AntigravityTheme.googleRed;
      badgeColor = AntigravityTheme.googleRed;
    } else if (line.startsWith('@@')) {
      bg = AntigravityTheme.googleBlue.withValues(alpha: 0.10);
      textColor = AntigravityTheme.googleBlue;
    }

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line indicator marker
          Container(
            width: 3,
            height: 16,
            margin: const EdgeInsets.only(right: 8, top: 2),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Line Number
          SizedBox(
            width: 36,
            child: Text(
              '$lineNum',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: AntigravityTheme.textMuted,
              ),
            ),
          ),
          // Diff Text
          Expanded(
            child: Text(
              line.isEmpty ? ' ' : line,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: textColor,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
