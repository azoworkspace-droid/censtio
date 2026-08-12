import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/permission_consent_service.dart';
import '../theme/app_theme.dart';

class PermissionConsentScreen extends StatefulWidget {
  const PermissionConsentScreen({required this.onComplete, super.key});

  final Future<void> Function() onComplete;

  @override
  State<PermissionConsentScreen> createState() =>
      _PermissionConsentScreenState();
}

class _PermissionConsentScreenState extends State<PermissionConsentScreen> {
  Map<AppPermissionKind, PermissionStatus> _statuses = const {};
  bool _isLoading = true;
  bool _isRequesting = false;

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  Future<void> _loadStatuses() async {
    final statuses = await PermissionConsentService.getStatuses();
    if (!mounted) return;
    setState(() {
      _statuses = statuses;
      _isLoading = false;
    });
  }

  Future<void> _requestPermissions() async {
    setState(() => _isRequesting = true);
    final statuses = await PermissionConsentService.requestAll();
    if (!mounted) return;
    setState(() {
      _statuses = statuses;
      _isRequesting = false;
    });
  }

  Future<void> _continue() async {
    await PermissionConsentService.markReviewed();
    await widget.onComplete();
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  bool _hasPermanentlyDeniedPermission() {
    return _statuses.values.any((status) => status.isPermanentlyDenied);
  }

  @override
  Widget build(BuildContext context) {
    final hasDeniedPermission = _statuses.values.any(
      (status) => !PermissionConsentService.isGranted(status),
    );

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppTheme.emerald.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.emerald.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    color: AppTheme.emerald,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'A few permissions,\nwith your control.',
                  style: AppTheme.displayLarge(),
                ),
                const SizedBox(height: 12),
                Text(
                  'Centsio uses these permissions only for the features you choose. Nothing is uploaded or shared without your action.',
                  style: AppTheme.bodyLarge(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                    border: Border.all(color: AppTheme.glassBorder),
                  ),
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < PermissionConsentService.items.length;
                        index++
                      ) ...[
                        _buildPermissionRow(
                          PermissionConsentService.items[index],
                        ),
                        if (index < PermissionConsentService.items.length - 1)
                          const Divider(
                            height: 28,
                            color: AppTheme.glassBorder,
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_hasPermanentlyDeniedPermission()) ...[
                  Text(
                    'Some access was previously denied. You can enable it in Settings when you are ready.',
                    style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Open Settings'),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading || _isRequesting
                        ? null
                        : hasDeniedPermission
                        ? _requestPermissions
                        : _continue,
                    child: _isRequesting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            hasDeniedPermission
                                ? 'Allow access'
                                : 'Continue to Centsio',
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _isLoading || _isRequesting ? null : _continue,
                  child: const Text('Continue without these permissions'),
                ),
                const SizedBox(height: 8),
                Text(
                  'You can change these choices anytime in your device Settings.',
                  textAlign: TextAlign.center,
                  style: AppTheme.labelSmall(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionRow(AppPermissionItem item) {
    final status = _statuses[item.kind];
    final isGranted =
        status != null && PermissionConsentService.isGranted(status);
    final isLoading = _isLoading;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.bgSurface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            _iconFor(item.kind),
            color: isGranted ? AppTheme.emerald : AppTheme.textSecondary,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: AppTheme.bodyLarge()),
              const SizedBox(height: 4),
              Text(
                item.description,
                style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
              ),
              if (!isLoading && status != null) ...[
                const SizedBox(height: 6),
                Text(
                  isGranted
                      ? 'Allowed'
                      : status.isPermanentlyDenied
                      ? 'Turn on in Settings'
                      : 'Not allowed yet',
                  style: AppTheme.labelSmall(
                    color: isGranted
                        ? AppTheme.emerald
                        : AppTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          isGranted ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
          color: isGranted ? AppTheme.emerald : AppTheme.textSecondary,
        ),
      ],
    );
  }

  IconData _iconFor(AppPermissionKind kind) {
    return switch (kind) {
      AppPermissionKind.camera => Icons.camera_alt_outlined,
      AppPermissionKind.photos => Icons.photo_library_outlined,
      AppPermissionKind.microphone => Icons.mic_none_rounded,
      AppPermissionKind.speech => Icons.graphic_eq_rounded,
    };
  }
}
