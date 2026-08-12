import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';
import '../theme/app_theme.dart';

/// Full-screen lock UI used by the app gate and when disabling the lock.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key, this.onUnlocked});

  /// When provided, the screen is embedded by [AppLockGate]. Otherwise it
  /// returns `true` to the route that opened it.
  final VoidCallback? onUnlocked;

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  final _passwordController = TextEditingController();
  AppLockMode _mode = AppLockMode.password;
  bool _modeReady = false;
  bool _biometricAvailable = false;
  bool _isBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepareBiometrics();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _prepareBiometrics() async {
    final mode = await AppLockService.getMode();
    if (!mounted) return;
    setState(() {
      _mode = mode;
      _modeReady = true;
    });

    if (mode == AppLockMode.password) return;

    final available = await AppLockService.canUseBiometrics();
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
    if (available) {
      await _unlockWithBiometrics();
    } else {
      setState(
        () => _error =
            'Face ID or Touch ID is unavailable. Enable it in device Settings.',
      );
    }
  }

  Future<void> _unlockWithBiometrics() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _error = null;
    });

    final authenticated = await AppLockService.authenticateBiometric();
    if (!mounted) return;
    setState(() => _isBusy = false);
    if (authenticated) {
      _finish();
    } else {
      setState(() => _error = 'Authentication cancelled or unsuccessful.');
    }
  }

  Future<void> _unlockWithPassword() async {
    if (_mode != AppLockMode.password) return;
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _error = 'Enter your app password or PIN.');
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
    });
    final valid = await AppLockService.verifyPassword(password);
    if (!mounted) return;
    setState(() => _isBusy = false);
    if (valid) {
      _finish();
    } else {
      setState(() => _error = 'Incorrect password or PIN.');
      _passwordController.clear();
    }
  }

  void _finish() {
    if (widget.onUnlocked != null) {
      widget.onUnlocked!();
    } else if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_modeReady) {
      return const Scaffold(
        backgroundColor: AppTheme.bgDeep,
        body: Center(child: CircularProgressIndicator(color: AppTheme.emerald)),
      );
    }

    final usesBiometrics = _mode == AppLockMode.biometrics;

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: GlassLockCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppTheme.emerald.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      color: AppTheme.emerald,
                      size: 42,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text('App Locked', style: AppTheme.headlineMedium()),
                  const SizedBox(height: 8),
                  Text(
                    usesBiometrics
                        ? 'Use Face ID, Touch ID, or your device passcode to access your financial information.'
                        : 'Enter your password or PIN to access your financial information.',
                    textAlign: TextAlign.center,
                    style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 26),
                  if (usesBiometrics && _biometricAvailable)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isBusy ? null : _unlockWithBiometrics,
                        icon: const Icon(Icons.face_rounded),
                        label: const Text('Use Face ID / Touch ID'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.emerald,
                          foregroundColor: AppTheme.bgDeep,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  if (!usesBiometrics) ...[
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      enabled: !_isBusy,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _unlockWithPassword(),
                      decoration: InputDecoration(
                        labelText: 'Password or PIN',
                        prefixIcon: const Icon(Icons.key_rounded),
                        filled: true,
                        fillColor: AppTheme.bgSurface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AppTheme.glassBorder,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _isBusy ? null : _unlockWithPassword,
                        child: const Text('Unlock'),
                      ),
                    ),
                  ] else if (!_biometricAvailable)
                    Text(
                      'This app is configured for Face ID / Touch ID. Enable device biometrics and reopen the app.',
                      textAlign: TextAlign.center,
                      style: AppTheme.bodyMedium(color: AppTheme.warningAmber),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: AppTheme.bodyMedium(color: AppTheme.errorRed),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppLockSetupScreen extends StatefulWidget {
  const AppLockSetupScreen({super.key});

  @override
  State<AppLockSetupScreen> createState() => _AppLockSetupScreenState();
}

class _AppLockSetupScreenState extends State<AppLockSetupScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  AppLockMode _selectedMode = AppLockMode.password;
  bool _obscurePassword = true;
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final password = _passwordController.text.trim();
    if (_selectedMode == AppLockMode.password) {
      if (password.length < 4) {
        setState(
          () => _error = 'Use at least 4 characters for your password or PIN.',
        );
        return;
      }
      if (password != _confirmController.text.trim()) {
        setState(() => _error = 'The passwords do not match.');
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await AppLockService.enable(
        mode: _selectedMode,
        password: _selectedMode == AppLockMode.password ? password : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = error is FormatException
              ? error.message
              : 'Could not enable app lock. Please try again.';
        });
      }
    }
  }

  Widget _buildModeOption({
    required AppLockMode mode,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final selected = _selectedMode == mode;
    return InkWell(
      onTap: _isSaving ? null : () => setState(() => _selectedMode = mode),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: selected ? AppTheme.emerald.withAlpha(24) : AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.emerald : AppTheme.glassBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? AppTheme.emerald : AppTheme.textSecondary,
              size: 28,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.titleLarge().copyWith(fontSize: 16),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? AppTheme.emerald : AppTheme.textHint,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDeep,
        title: Text('Set Up App Lock', style: AppTheme.headlineMedium()),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            GlassLockCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.security_rounded,
                    color: AppTheme.emerald,
                    size: 36,
                  ),
                  const SizedBox(height: 16),
                  Text('Protect your account', style: AppTheme.titleLarge()),
                  const SizedBox(height: 8),
                  Text(
                    'Choose one way to protect this app. You can change it later from Settings.',
                    style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  _buildModeOption(
                    mode: AppLockMode.password,
                    icon: Icons.key_rounded,
                    title: 'Password / PIN',
                    description: 'Unlock with a password or PIN you create.',
                  ),
                  const SizedBox(height: 12),
                  _buildModeOption(
                    mode: AppLockMode.biometrics,
                    icon: Icons.face_rounded,
                    title: 'Face ID / Touch ID',
                    description: 'Use biometrics protected by your device.',
                  ),
                  if (_selectedMode == AppLockMode.password) ...[
                    const SizedBox(height: 20),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      enabled: !_isSaving,
                      decoration: InputDecoration(
                        labelText: 'Password or PIN',
                        prefixIcon: const Icon(Icons.key_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _confirmController,
                      obscureText: _obscurePassword,
                      enabled: !_isSaving,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(),
                      decoration: const InputDecoration(
                        labelText: 'Confirm password or PIN',
                        prefixIcon: Icon(Icons.check_circle_outline_rounded),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 20),
                    Text(
                      'Your device will ask for Face ID or Touch ID when you open the app. The device passcode can be used by the operating system as a recovery method.',
                      style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      style: AppTheme.bodyMedium(color: AppTheme.errorRed),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      child: const Text('Enable App Lock'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GlassLockCard extends StatelessWidget {
  const GlassLockCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: child,
    );
  }
}
