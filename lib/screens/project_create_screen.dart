import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../models/project.dart';
import '../providers/project_provider.dart';

class ProjectCreateScreen extends StatefulWidget {
  const ProjectCreateScreen({super.key});

  @override
  State<ProjectCreateScreen> createState() => _ProjectCreateScreenState();
}

class _ProjectCreateScreenState extends State<ProjectCreateScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _customPathController = TextEditingController();
  String _currentSelectedPath = '~';
  bool _isManualPathMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProjectProvider>().browseDirectory('~');
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _customPathController.dispose();
    super.dispose();
  }

  String _extractFolderName(String path) {
    final cleaned = path.replaceAll('\\', '/');
    final parts = cleaned.split('/').where((s) => s.isNotEmpty && s != ':').toList();
    if (parts.isNotEmpty) {
      final last = parts.last;
      // If ends with colon like C:, return drive or workspace
      if (last.endsWith(':')) return 'Drive_${last[0]}';
      return last;
    }
    return 'project';
  }

  void _onFolderSelected(String folderName, String fullPath) {
    setState(() {
      _currentSelectedPath = fullPath;
      _nameController.text = folderName;
      if (_isManualPathMode) {
        _customPathController.text = fullPath;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final projProvider = context.watch<ProjectProvider>();
    final dir = projProvider.currentBrowsedDir;
    final activePath = dir?.currentPath ?? _currentSelectedPath;

    // Auto-populate name if empty
    if (_nameController.text.isEmpty && activePath.isNotEmpty && activePath != '/' && activePath != '~') {
      _nameController.text = _extractFolderName(activePath);
    }

    return Scaffold(
      backgroundColor: AntigravityTheme.background,
      appBar: AppBar(
        title: const Text('Create Remote Project'),
        actions: [
          IconButton(
            icon: Icon(
              _isManualPathMode ? Icons.folder_open_outlined : Icons.edit_outlined,
              size: 20,
            ),
            tooltip: _isManualPathMode ? 'Browse Folders' : 'Type Custom Path',
            onPressed: () {
              setState(() {
                _isManualPathMode = !_isManualPathMode;
                if (_isManualPathMode) {
                  _customPathController.text = activePath;
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Project Configuration Box
          Container(
            padding: const EdgeInsets.all(16),
            color: AntigravityTheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Project Name',
                    hintText: 'e.g. backend-microservice',
                    prefixIcon: Icon(Icons.rocket_launch_outlined, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                if (!_isManualPathMode) ...[
                  Row(
                    children: [
                      const Icon(Icons.folder_special_outlined,
                          size: 16, color: AntigravityTheme.googleBlue),
                      const SizedBox(width: 6),
                      const Text(
                        'Target Project Directory:',
                        style: TextStyle(
                          fontSize: 12,
                          color: AntigravityTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      _buildQuickJump(context, 'C:\\', 'C:/'),
                      const SizedBox(width: 4),
                      _buildQuickJump(context, 'Home', '~'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AntigravityTheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AntigravityTheme.border),
                    ),
                    child: Text(
                      activePath,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: AntigravityTheme.googleGreen,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: _customPathController,
                    style: const TextStyle(
                      color: AntigravityTheme.googleGreen,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Host Root Directory Path',
                      hintText: 'C:/flut/my_project',
                      prefixIcon: Icon(Icons.folder_open_outlined, size: 18),
                    ),
                    onChanged: (val) {
                      _currentSelectedPath = val.trim();
                      if (val.trim().isNotEmpty) {
                        _nameController.text = _extractFolderName(val.trim());
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: AntigravityTheme.border),

          // Explorer Section Title
          if (!_isManualPathMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AntigravityTheme.surfaceContainer.withValues(alpha: 0.5),
              child: Row(
                children: [
                  const Icon(Icons.account_tree_outlined, size: 14, color: AntigravityTheme.textSecondary),
                  const SizedBox(width: 6),
                  const Text(
                    'REMOTE HOST EXPLORER',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.bold,
                      color: AntigravityTheme.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 16, color: AntigravityTheme.textSecondary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => projProvider.browseDirectory(activePath),
                  ),
                ],
              ),
            ),

          // Directory Listing or Manual Mode
          Expanded(
            child: _isManualPathMode
                ? _buildManualModeHelp()
                : projProvider.isLoading
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(strokeWidth: 2),
                            SizedBox(height: 12),
                            Text(
                              'Browsing remote host...',
                              style: TextStyle(fontSize: 12, color: AntigravityTheme.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : _buildDirectoryList(projProvider, dir, activePath),
          ),

          // Action Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AntigravityTheme.surface,
              border: Border(top: BorderSide(color: AntigravityTheme.border)),
            ),
            child: SafeArea(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AntigravityTheme.googleBlue,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: projProvider.isCreating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                        ),
                      )
                    : const Icon(Icons.check_circle_outline, color: Colors.black),
                label: Text(
                  projProvider.isCreating ? 'Creating Project...' : 'Create & Select Project',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                onPressed: projProvider.isCreating
                    ? null
                    : () {
                        final name = _nameController.text.trim().isEmpty
                            ? _extractFolderName(activePath)
                            : _nameController.text.trim();

                        final selectedRoot = _isManualPathMode
                            ? _customPathController.text.trim()
                            : activePath;

                        projProvider.createNewProject(name, selectedRoot);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Project "$name" added at $selectedRoot'),
                            backgroundColor: AntigravityTheme.surfaceContainerHigh,
                          ),
                        );
                        Navigator.pop(context);
                      },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickJump(BuildContext context, String label, String targetPath) {
    return InkWell(
      onTap: () {
        context.read<ProjectProvider>().browseDirectory(targetPath);
        _nameController.text = _extractFolderName(targetPath);
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AntigravityTheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AntigravityTheme.borderSubtle),
        ),
        child: Text(label, style: const TextStyle(fontSize: 10, color: AntigravityTheme.googleBlue)),
      ),
    );
  }

  Widget _buildManualModeHelp() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.terminal_outlined, size: 48, color: AntigravityTheme.googleBlue.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          const Text(
            'Direct Path Entry Mode',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the absolute path on your host machine where this workspace or codebase is located.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AntigravityTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryList(
    ProjectProvider provider,
    RemoteDirectory? dir,
    String activePath,
  ) {
    final folders = dir?.folders ?? [];
    final files = dir?.files ?? [];

    if (dir == null || (folders.isEmpty && files.isEmpty)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_off_outlined, size: 36, color: AntigravityTheme.textSecondary),
            const SizedBox(height: 8),
            const Text('Folder is empty or unreadable', style: TextStyle(color: AntigravityTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.arrow_upward, size: 14),
              label: const Text('Go to Home'),
              onPressed: () => provider.browseDirectory('~'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        // Parent folder navigation
        if (dir.parentPath.isNotEmpty && dir.currentPath != '/' && dir.currentPath != dir.parentPath)
          ListTile(
            dense: true,
            leading: const Icon(Icons.arrow_upward_rounded, color: AntigravityTheme.googleBlue, size: 20),
            title: const Text(
              '.. (Parent Folder)',
              style: TextStyle(color: AntigravityTheme.googleBlue, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            subtitle: Text(dir.parentPath, style: const TextStyle(fontSize: 11, color: AntigravityTheme.textMuted)),
            onTap: () {
              final parentName = _extractFolderName(dir.parentPath);
              _onFolderSelected(parentName, dir.parentPath);
              provider.browseDirectory(dir.parentPath);
            },
          ),

        // Folders
        ...folders.map((folder) {
          return ListTile(
            dense: true,
            leading: const Icon(Icons.folder_rounded, color: AntigravityTheme.googleAmber, size: 20),
            title: Text(
              folder,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18, color: AntigravityTheme.textSecondary),
            onTap: () {
              final newPath = activePath == '/' || activePath == 'C:/'
                  ? '${activePath.replaceAll(RegExp(r'/+$'), '')}/$folder'
                  : '$activePath/$folder';
              _onFolderSelected(folder, newPath);
              provider.browseDirectory(newPath);
            },
          );
        }),

        // Files (read-only markers)
        ...files.map((file) {
          return ListTile(
            dense: true,
            leading: const Icon(Icons.insert_drive_file_outlined, color: AntigravityTheme.textSecondary, size: 18),
            title: Text(
              file,
              style: const TextStyle(fontSize: 12, color: AntigravityTheme.textSecondary),
            ),
          );
        }),
      ],
    );
  }
}
