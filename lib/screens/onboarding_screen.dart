import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/onboarding_options.dart';
import '../providers/business_profile_provider.dart';
import '../providers/currency_provider.dart';
import '../providers/tax_rate_provider.dart';
import '../screens/main_nav_screen.dart';
import '../screens/paywall_screen.dart';
import '../services/analytics_service.dart';
import '../services/revenuecat_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

/// Progressive three-step setup for a new freelancer, business, or individual.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _appName = 'Centsio AI: Invoice Maker';

  final _nameController = TextEditingController();
  final _taglineController = TextEditingController();
  final _taxNumberController = TextEditingController();
  final _taxRateController = TextEditingController();
  final _paymentDetailsController = TextEditingController();
  final _nameFocusNode = FocusNode();

  int _step = 0;
  String _profileType = 'Freelancer';
  String? _countryCode;
  String _currencyCode = 'USD';
  String? _taxIdLabel;
  String? _paymentMethod;
  String? _logoPath;
  bool _isSubmitting = false;
  // Render the first step immediately; the local draft is hydrated without
  // blocking the first frame or making the welcome screen feel slow.
  bool _isRestoring = false;
  bool _nameWasTracked = false;
  bool _logoSkipped = false;
  String? _profileError;
  String? _localeError;
  String? _completionError;
  Timer? _draftSaveTimer;

  @override
  void initState() {
    super.initState();
    unawaited(AnalyticsService.trackOnce('onboarding_started'));
    unawaited(_restoreDraft());
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _nameController.dispose();
    _taglineController.dispose();
    _taxNumberController.dispose();
    _taxRateController.dispose();
    _paymentDetailsController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    final draft = await SettingsService.getOnboardingDraft();
    if (!mounted) return;

    _nameController.text = draft.name;
    _taglineController.text = draft.tagline;
    _taxNumberController.text = draft.taxIdValue;
    _taxRateController.text = draft.taxRate;
    _paymentDetailsController.text = draft.paymentDetails;

    setState(() {
      _step = draft.step;
      _profileType = draft.profileType;
      _countryCode = draft.countryCode;
      _currencyCode = currencyForCode(draft.currencyCode).code;
      _taxIdLabel = draft.taxIdLabel;
      _paymentMethod = draft.paymentMethod;
      _logoPath = draft.logoPath;
      _isRestoring = false;
    });
    _trackStepViewed();
  }

  void _scheduleDraftSave() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_saveDraft());
    });
  }

  Future<void> _saveDraft() {
    return SettingsService.saveOnboardingDraft(
      step: _step,
      profileType: _profileType,
      name: _nameController.text,
      tagline: _taglineController.text,
      logoPath: _logoPath,
      countryCode: _countryCode,
      currencyCode: _currencyCode,
      taxIdLabel: _taxIdLabel,
      taxIdValue: _taxNumberController.text,
      taxRate: _taxRateController.text,
      paymentMethod: _paymentMethod,
      paymentDetails: _paymentDetailsController.text,
    );
  }

  void _trackStepViewed() {
    unawaited(
      AnalyticsService.track(
        'onboarding_step_viewed',
        properties: {'step': _step + 1},
      ),
    );
  }

  void _setStep(int newStep) {
    if (newStep == _step || newStep < 0 || newStep > 2) return;
    setState(() => _step = newStep);
    _trackStepViewed();
    unawaited(_saveDraft());
  }

  bool get _isStepOneComplete => _nameController.text.trim().isNotEmpty;

  bool get _isTaxRateValid {
    final raw = _taxRateController.text.trim();
    if (raw.isEmpty) return true;
    final value = double.tryParse(raw);
    return value != null && value >= 0 && value <= 100;
  }

  bool get _isStepTwoComplete =>
      _countryCode != null && _currencyCode.isNotEmpty && _isTaxRateValid;

  String? get _taxRateError {
    final raw = _taxRateController.text.trim();
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null) return 'Enter a number from 0 to 100.';
    if (value < 0 || value > 100) return 'Enter a rate from 0 to 100.';
    return null;
  }

  Future<void> _onContinue() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_step == 0) {
      if (!_isStepOneComplete) {
        setState(() {
          _profileError = 'Please enter your business name or full name.';
        });
        return;
      }
      _setStep(1);
    } else if (_step == 1) {
      if (!_isStepTwoComplete) {
        setState(() {
          _localeError = _countryCode == null
              ? 'Please select a country / region to continue.'
              : _taxRateError ??
                    'Please complete the required invoice preferences.';
        });
        return;
      }
      _setStep(2);
    } else {
      await _completeOnboarding();
    }
  }

  Future<void> _onBack() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_step > 0) _setStep(_step - 1);
  }

  void _trackSkip() {
    unawaited(
      AnalyticsService.track(
        'onboarding_skipped',
        properties: {'step': _step + 1},
      ),
    );
  }

  Future<void> _onLogoTap() async {
    unawaited(AnalyticsService.track('logo_upload_tapped'));
    final isPro = await RevenueCatService.isProUser();
    if (!isPro && mounted) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
      return;
    }

    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 85,
    );
    if (pickedFile != null && mounted) {
      setState(() {
        _logoPath = pickedFile.path;
        _logoSkipped = false;
      });
      unawaited(_saveDraft());
    }
  }

  void _skipLogo() {
    _trackSkip();
    setState(() {
      _logoSkipped = true;
      if (!_isStepOneComplete) {
        _profileError = 'Please enter your business name or full name.';
      }
    });
    _scheduleDraftSave();
  }

  Future<void> _completeOnboarding() async {
    if (_isSubmitting) return;

    if (!_isStepOneComplete) {
      setState(() {
        _step = 0;
        _profileError = 'Please enter your business name or full name.';
      });
      return;
    }
    if (!_isStepTwoComplete) {
      setState(() {
        _step = 1;
        _localeError = _countryCode == null
            ? 'Select a country / region to continue.'
            : _taxRateError ?? 'Complete the required invoice preferences.';
      });
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSubmitting = true;
      _completionError = null;
    });

    try {
      final name = _nameController.text.trim();
      final tagline = _taglineController.text.trim().isEmpty
          ? 'Professional Invoicing Platform'
          : _taglineController.text.trim();
      final taxNumber = _taxNumberController.text.trim();
      final taxRate = double.tryParse(_taxRateController.text.trim()) ?? 0.0;
      final paymentDetails = _paymentDetailsController.text.trim();
      final storedPaymentDetails = _paymentMethod == null
          ? null
          : paymentDetails.isEmpty
          ? 'Payment method: $_paymentMethod'
          : 'Payment method: $_paymentMethod\nDetails: $paymentDetails';

      await SettingsService.saveBusinessProfile(
        name: name,
        tagline: tagline,
        profileType: _profileType,
        country: countryForCode(_countryCode)?.name,
        bankDetails: storedPaymentDetails,
        logoPath: _logoPath,
      );
      await SettingsService.saveTaxIdDetails(
        _taxIdLabel ?? 'Tax ID',
        taxNumber,
      );
      await SettingsService.savePaymentSelection(
        method: _paymentMethod,
        details: paymentDetails,
      );
      await SettingsService.saveCurrencySelection(
        code: _currencyCode,
        symbol: currencyForCode(_currencyCode).symbol,
      );
      await ref
          .read(currencyCodeProvider.notifier)
          .setCurrencyCode(_currencyCode);
      await ref
          .read(currencySymbolProvider.notifier)
          .setCurrency(currencyForCode(_currencyCode).symbol);
      await ref.read(defaultTaxRateProvider.notifier).setTaxRate(taxRate);
      await ref.read(businessProfileProvider.notifier).refresh();
      await SettingsService.setOnboardingCompleted();
      await SettingsService.clearOnboardingDraft();
      await AnalyticsService.track('onboarding_completed');

      if (!mounted) return;
      setState(() => _isSubmitting = false);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainNavScreen()),
      );
    } catch (error, stackTrace) {
      debugPrint('Onboarding completion failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _completionError =
            'We could not finish setup. Your progress is saved—please try again.';
      });
    }
  }

  void _skipOptionalTaxDetails() {
    _trackSkip();
    if (!_isStepTwoComplete) {
      setState(() {
        _localeError = _countryCode == null
            ? 'Select a country / region to continue.'
            : _taxRateError ?? 'Complete the required invoice preferences.';
      });
      return;
    }
    _setStep(2);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) unawaited(_saveDraft());
      },
      child: Scaffold(
        backgroundColor: AppTheme.bgDeep,
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            const _BackgroundOrbs(),
            SafeArea(
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          fit: StackFit.expand,
                          alignment: Alignment.topCenter,
                          children: [...previousChildren, ?currentChild],
                        );
                      },
                      child: _isRestoring
                          ? const Center(
                              key: ValueKey('restoring'),
                              child: CircularProgressIndicator(
                                color: AppTheme.emerald,
                                strokeWidth: 2.5,
                              ),
                            )
                          : _buildCurrentStep(),
                    ),
                  ),
                  _buildBottomActions(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Column(
        children: [
          Row(
            children: [
              if (_step > 0)
                Semantics(
                  button: true,
                  label: 'Back',
                  child: IconButton(
                    onPressed: _isSubmitting ? null : _onBack,
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppTheme.textPrimary,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                  ),
                )
              else
                const SizedBox(width: 44),
              const Spacer(),
              Text(
                'Step ${_step + 1} of 3',
                semanticsLabel: 'Step ${_step + 1} of 3',
                style: AppTheme.labelSmall(color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(3, (index) {
              final active = index <= _step;
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 4,
                  margin: EdgeInsets.only(right: index == 2 ? 0 : 6),
                  decoration: BoxDecoration(
                    color: active
                        ? AppTheme.emerald
                        : AppTheme.textSecondary.withAlpha(45),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: active
                        ? [
                            const BoxShadow(
                              color: AppTheme.emeraldGlow,
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    final child = switch (_step) {
      0 => _buildProfileStep(),
      1 => _buildTaxStep(),
      _ => _buildPaymentStep(),
    };
    return SingleChildScrollView(
      key: ValueKey<int>(_step),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: child,
    );
  }

  Widget _buildStepHeader({required String title, required String subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.displayLarge().copyWith(fontSize: 32)),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: AppTheme.bodyLarge(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileStep() {
    final hasLogo = _logoPath != null && File(_logoPath!).existsSync();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          title: 'Welcome to $_appName',
          subtitle:
              'Create professional invoices and track your business finances in seconds.',
        ),
        _buildSectionCard(
          title: 'Profile type',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['Freelancer', 'Business', 'Individual'].map((type) {
              final selected = _profileType == type;
              return ChoiceChip(
                selected: selected,
                label: Text(type),
                onSelected: (_) {
                  setState(() => _profileType = type);
                  unawaited(
                    AnalyticsService.track(
                      'profile_type_selected',
                      properties: {'profile_type': type},
                    ),
                  );
                  _scheduleDraftSave();
                },
                selectedColor: AppTheme.emerald,
                backgroundColor: AppTheme.bgSurface,
                side: BorderSide(
                  color: selected ? AppTheme.emerald : AppTheme.glassBorder,
                ),
                labelStyle: AppTheme.bodyMedium(
                  color: selected ? AppTheme.bgDeep : AppTheme.textPrimary,
                ).copyWith(fontWeight: FontWeight.w600),
                showCheckmark: false,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
        _buildSectionCard(
          title: 'Your details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextField(
                controller: _nameController,
                focusNode: _nameFocusNode,
                label: 'Business name or full name',
                required: true,
                hint: 'e.g. Acme Studio or Alex Vance',
                textInputAction: TextInputAction.next,
                onChanged: (value) {
                  setState(() {
                    _profileError = value.trim().isEmpty ? _profileError : null;
                  });
                  if (value.trim().isNotEmpty && !_nameWasTracked) {
                    _nameWasTracked = true;
                    unawaited(
                      AnalyticsService.track('business_name_completed'),
                    );
                  }
                  _scheduleDraftSave();
                },
              ),
              if (_profileError != null) ...[
                const SizedBox(height: 6),
                _buildFieldError(_profileError!),
              ],
              const SizedBox(height: 14),
              _buildTextField(
                controller: _taglineController,
                label: 'What do you do?',
                optional: true,
                hint: 'e.g. Senior mobile engineer & consultant',
                textInputAction: TextInputAction.done,
                onChanged: (_) => _scheduleDraftSave(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildLogoCard(hasLogo),
      ],
    );
  }

  Widget _buildLogoCard(bool hasLogo) {
    return _buildSectionCard(
      title: 'Company logo',
      trailing: _proBadge(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Optional · Add your logo to branded invoices when you are ready.',
            style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 14),
          Semantics(
            button: true,
            label: hasLogo ? 'Change company logo' : 'Upload company logo',
            hint: 'Pro feature. Opens the photo library.',
            child: InkWell(
              onTap: _onLogoTap,
              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
              child: Container(
                constraints: const BoxConstraints(minHeight: 72),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                  border: Border.all(
                    color: hasLogo ? AppTheme.emerald : AppTheme.glassBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppTheme.emerald.withAlpha(18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: hasLogo
                          ? Image.file(File(_logoPath!), fit: BoxFit.cover)
                          : const Icon(
                              Icons.add_a_photo_outlined,
                              color: AppTheme.emerald,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        hasLogo ? 'Change logo' : 'Upload logo',
                        style: AppTheme.bodyLarge(color: AppTheme.textPrimary),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppTheme.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isSubmitting ? null : _skipLogo,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                foregroundColor: AppTheme.textSecondary,
              ),
              child: Text(_logoSkipped ? 'Logo skipped' : 'Skip for now'),
            ),
          ),
          if (_logoSkipped)
            Text(
              'You can add a logo later in Settings.',
              style: AppTheme.bodyMedium(
                color: AppTheme.textSecondary,
              ).copyWith(fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildTaxStep() {
    final currency = currencyForCode(_currencyCode);
    final country = countryForCode(_countryCode);
    final suggested = suggestedTaxIds(_countryCode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          title: 'Set up your invoice preferences',
          subtitle:
              'Choose the defaults that will save you time on every invoice.',
        ),
        _buildSectionCard(
          title: 'Locale',
          child: Column(
            children: [
              _buildSelectionField(
                label: 'Country / region',
                value: country == null
                    ? null
                    : '${country.name} · ${country.code}',
                placeholder: 'Select country / region',
                required: true,
                icon: Icons.public_rounded,
                onTap: _showCountryPicker,
              ),
              const SizedBox(height: 12),
              _buildSelectionField(
                label: 'Preferred currency',
                value:
                    '${currency.code} · ${currency.name} (${currency.symbol})',
                placeholder: 'Select currency',
                required: true,
                icon: Icons.currency_exchange_rounded,
                onTap: _showCurrencyPicker,
              ),
            ],
          ),
        ),
        if (_localeError != null) ...[
          const SizedBox(height: 8),
          _buildInlineError(_localeError!),
        ],
        const SizedBox(height: 14),
        _buildSectionCard(
          title: 'Tax details',
          trailing: _optionalBadge(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tax ID details are optional and can be added later in Settings.',
                style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 14),
              Text(
                'Tax ID type',
                style: AppTheme.labelSmall(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              _buildSelectionField(
                label: '',
                value: _taxIdLabel,
                placeholder: 'Select a tax ID type',
                icon: Icons.badge_outlined,
                onTap: _showTaxIdPicker,
              ),
              if (suggested.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  country == null
                      ? 'Common options'
                      : 'Suggested for ${country.name}',
                  style: AppTheme.labelSmall(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: suggested.take(4).map((option) {
                    final selected = option.label == _taxIdLabel;
                    return ActionChip(
                      label: Text(option.label),
                      onPressed: () => _selectTaxId(option),
                      backgroundColor: selected
                          ? AppTheme.emerald.withAlpha(30)
                          : AppTheme.bgSurface,
                      side: BorderSide(
                        color: selected
                            ? AppTheme.emerald
                            : AppTheme.glassBorder,
                      ),
                      labelStyle: AppTheme.bodyMedium(
                        color: selected
                            ? AppTheme.emerald
                            : AppTheme.textPrimary,
                      ),
                    );
                  }).toList(),
                ),
              ],
              if (_taxIdLabel != null) ...[
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _taxNumberController,
                  label: 'Tax number',
                  optional: true,
                  hint: 'Enter your $_taxIdLabel',
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _scheduleDraftSave(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildSectionCard(
          title: 'Default tax rate for new invoices',
          trailing: _optionalBadge(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _taxRateController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                style: AppTheme.bodyLarge(color: AppTheme.textPrimary),
                onChanged: (_) => setState(() {}),
                validator: (_) => _taxRateError,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: _inputDecoration(
                  label: 'Rate (optional)',
                  hint: 'Leave empty if you do not charge tax',
                  suffixText: '%',
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['No tax', '5%', '10%', '20%'].map((preset) {
                  final selected = preset == 'No tax'
                      ? _taxRateController.text.trim().isEmpty ||
                            _taxRateController.text.trim() == '0'
                      : _taxRateController.text.trim() ==
                            preset.substring(0, preset.length - 1);
                  return ChoiceChip(
                    selected: selected,
                    label: Text(preset),
                    onSelected: (_) {
                      setState(() {
                        _taxRateController.text = preset == 'No tax'
                            ? ''
                            : preset.substring(0, preset.length - 1);
                      });
                      _scheduleDraftSave();
                    },
                    selectedColor: AppTheme.emerald,
                    backgroundColor: AppTheme.bgSurface,
                    side: BorderSide(
                      color: selected ? AppTheme.emerald : AppTheme.glassBorder,
                    ),
                    labelStyle: AppTheme.bodyMedium(
                      color: selected ? AppTheme.bgDeep : AppTheme.textPrimary,
                    ),
                    showCheckmark: false,
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Text(
                'Used as the default for new invoices. You can change it later.',
                style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              Text(
                'Tax calculations are estimates and are not tax advice.',
                style: AppTheme.bodyMedium(color: AppTheme.warningAmber),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentStep() {
    final selectedOption = onboardingPaymentMethods.where(
      (method) => method.label == _paymentMethod,
    );
    final paymentOption = selectedOption.isEmpty ? null : selectedOption.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          title: 'Choose how clients can pay you',
          subtitle:
              'Add a payment option now or keep it blank and finish later.',
        ),
        _buildSectionCard(
          title: 'Payment details',
          trailing: _optionalBadge(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'These details can appear at the bottom of your invoices.',
                style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: onboardingPaymentMethods.map((method) {
                  final selected = method.label == _paymentMethod;
                  return ChoiceChip(
                    selected: selected,
                    label: Text('${method.icon}  ${method.label}'),
                    onSelected: (_) {
                      setState(() {
                        _paymentMethod = method.label;
                        if (!method.requiresDetails) {
                          _paymentDetailsController.clear();
                        }
                      });
                      unawaited(
                        AnalyticsService.track(
                          'payment_method_selected',
                          properties: {'payment_method': method.label},
                        ),
                      );
                      _scheduleDraftSave();
                    },
                    selectedColor: AppTheme.emerald,
                    backgroundColor: AppTheme.bgSurface,
                    side: BorderSide(
                      color: selected ? AppTheme.emerald : AppTheme.glassBorder,
                    ),
                    labelStyle: AppTheme.bodyMedium(
                      color: selected ? AppTheme.bgDeep : AppTheme.textPrimary,
                    ),
                    showCheckmark: false,
                  );
                }).toList(),
              ),
              if (paymentOption == null) ...[
                const SizedBox(height: 12),
                Text(
                  'No payment method selected. You can add one later.',
                  style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                ),
              ] else if (paymentOption.requiresDetails) ...[
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _paymentDetailsController,
                  label: paymentOption.label,
                  optional: true,
                  hint: paymentOption.hint,
                  maxLines:
                      paymentOption.label == 'Other' ||
                          paymentOption.label == 'Bank transfer'
                      ? 3
                      : 1,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => _scheduleDraftSave(),
                ),
              ] else ...[
                const SizedBox(height: 14),
                Text(
                  'No additional details needed for cash payments.',
                  style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'You can update payment details anytime from Profile settings.',
          style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
        ),
        if (_completionError != null) ...[
          const SizedBox(height: 12),
          _buildInlineError(_completionError!),
        ],
      ],
    );
  }

  Widget _buildBottomActions() {
    final buttonLabel = _step == 2 ? 'Start Creating Invoices' : 'Continue';

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: Row(
        children: [
          if (_step > 0)
            TextButton.icon(
              onPressed: _isSubmitting ? null : _onBack,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 52),
                foregroundColor: AppTheme.textSecondary,
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Back'),
            ),
          if (_step > 0) const SizedBox(width: 8),
          if (_step == 1 || _step == 2)
            TextButton(
              onPressed: _isSubmitting
                  ? null
                  : () async {
                      if (_step == 1) {
                        _skipOptionalTaxDetails();
                      } else {
                        _trackSkip();
                        await _completeOnboarding();
                      }
                    },
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 52),
                foregroundColor: AppTheme.textSecondary,
              ),
              child: const Text('Skip for now'),
            ),
          const Spacer(),
          Flexible(
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _onContinue,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(44, 52),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  backgroundColor: AppTheme.emerald,
                  disabledBackgroundColor: AppTheme.bgSurface,
                  foregroundColor: AppTheme.bgDeep,
                  disabledForegroundColor: AppTheme.textHint,
                  elevation: 8,
                  shadowColor: AppTheme.emeraldGlow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: AppTheme.bgDeep,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              buttonLabel,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.bodyLarge(color: AppTheme.bgDeep),
                            ),
                          ),
                          const SizedBox(width: 7),
                          const Icon(Icons.arrow_forward_rounded, size: 20),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      borderRadius: AppTheme.radiusLG,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.titleLarge(color: AppTheme.textPrimary),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildInlineError(String message) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            Icons.error_outline_rounded,
            color: AppTheme.errorRed,
            size: 18,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: AppTheme.bodyMedium(color: AppTheme.errorRed),
          ),
        ),
      ],
    );
  }

  Widget _buildFieldError(String message) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.error_outline_rounded,
            color: AppTheme.errorRed,
            size: 15,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: AppTheme.bodyMedium(
              color: AppTheme.errorRed,
            ).copyWith(fontSize: 12, height: 1.25),
          ),
        ),
      ],
    );
  }

  Widget _proBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.orange.withAlpha(28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.orange.withAlpha(100)),
      ),
      child: Text('PRO', style: AppTheme.labelSmall(color: AppTheme.orange)),
    );
  }

  Widget _optionalBadge() {
    return Text(
      'Optional',
      style: AppTheme.labelSmall(color: AppTheme.textSecondary),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    FocusNode? focusNode,
    required String label,
    String? hint,
    bool required = false,
    bool optional = false,
    int maxLines = 1,
    TextInputAction? textInputAction,
    ValueChanged<String>? onChanged,
    String? Function(String?)? validator,
    String? errorText,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      maxLines: maxLines,
      textInputAction: textInputAction,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onChanged: onChanged,
      style: AppTheme.bodyLarge(color: AppTheme.textPrimary),
      decoration: _inputDecoration(
        label: label,
        hint: hint,
        required: required,
        optional: optional,
        errorText: errorText,
      ),
    );
  }

  InputDecoration _inputDecoration({
    String? label,
    String? hint,
    bool required = false,
    bool optional = false,
    String? suffixText,
    String? errorText,
  }) {
    final labelText = label == null || label.isEmpty
        ? null
        : '$label${required
              ? '  • Required'
              : optional
              ? '  • Optional'
              : ''}';
    return InputDecoration(
      labelText: labelText,
      labelStyle: AppTheme.bodyMedium(color: AppTheme.textSecondary),
      hintText: hint,
      hintStyle: AppTheme.bodyMedium(color: AppTheme.textHint),
      suffixText: suffixText,
      suffixStyle: AppTheme.bodyMedium(color: AppTheme.textSecondary),
      errorText: errorText,
      errorStyle: AppTheme.bodyMedium(
        color: AppTheme.errorRed,
      ).copyWith(fontSize: 12, height: 1.25),
      filled: true,
      fillColor: AppTheme.bgSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSM),
        borderSide: const BorderSide(color: AppTheme.glassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSM),
        borderSide: const BorderSide(color: AppTheme.emerald, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSM),
        borderSide: const BorderSide(color: AppTheme.errorRed),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSM),
        borderSide: const BorderSide(color: AppTheme.errorRed, width: 1.5),
      ),
    );
  }

  Widget _buildSelectionField({
    required String label,
    required String? value,
    required String placeholder,
    required VoidCallback onTap,
    IconData? icon,
    bool required = false,
  }) {
    return Semantics(
      button: true,
      label: label.isEmpty ? placeholder : label,
      value: value ?? placeholder,
      hint: 'Double tap to choose',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSM),
        child: InputDecorator(
          // Keep the label floating for empty selectors so it never collides
          // with the placeholder text.
          isEmpty: label.isEmpty,
          decoration: _inputDecoration(
            label: label.isEmpty
                ? null
                : '$label${required ? '  • Required' : ''}',
          ).copyWith(prefixIcon: icon == null ? null : Icon(icon)),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value ?? placeholder,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyLarge(
                    color: value == null
                        ? AppTheme.textHint
                        : AppTheme.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCountryPicker() async {
    final selected = await showModalBottomSheet<CountryOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchPickerSheet<CountryOption>(
        title: 'Country / region',
        items: onboardingCountries,
        selectedKey: _countryCode,
        searchText: (item) => item.searchableText,
        itemKey: (item) => item.code,
        titleBuilder: (item) => item.name,
        subtitleBuilder: (item) => item.code,
      ),
    );
    if (selected == null || !mounted) return;
    // Country selection only changes tax-ID suggestions. Never overwrite a
    // currency the user already selected, even when the country has a common
    // local currency.
    setState(() {
      _countryCode = selected.code;
      _localeError = null;
    });
    _scheduleDraftSave();
  }

  Future<void> _showCurrencyPicker() async {
    final selected = await showModalBottomSheet<CurrencyOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchPickerSheet<CurrencyOption>(
        title: 'Preferred currency',
        items: onboardingCurrencies,
        selectedKey: _currencyCode,
        searchText: (item) => item.searchableText,
        itemKey: (item) => item.code,
        titleBuilder: (item) => '${item.code} · ${item.name}',
        subtitleBuilder: (item) => item.symbol,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _currencyCode = selected.code;
      _localeError = null;
    });
    unawaited(
      AnalyticsService.track(
        'currency_selected',
        properties: {'currency_code': selected.code},
      ),
    );
    _scheduleDraftSave();
  }

  Future<void> _showTaxIdPicker() async {
    final selected = await showModalBottomSheet<TaxIdOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchPickerSheet<TaxIdOption>(
        title: 'Tax ID type',
        items: onboardingTaxIds,
        selectedKey: _taxIdLabel,
        searchText: (item) => item.searchableText,
        itemKey: (item) => item.label,
        titleBuilder: (item) => item.label,
        subtitleBuilder: (item) => item.description,
      ),
    );
    if (selected == null || !mounted) return;
    await _selectTaxId(selected);
  }

  Future<void> _selectTaxId(TaxIdOption option) async {
    if (option.label == 'SSN') {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: Text('Sensitive identifier', style: AppTheme.titleLarge()),
          content: Text(
            'Only use SSN when it is legally required for your invoices. Keep it private and do not share it unless you trust the recipient.',
            style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    setState(() {
      _taxIdLabel = option.label;
      if (_taxIdLabel == 'Other' || _taxIdLabel == 'Tax ID') {
        // Keep an existing number if the user is only changing the label.
      }
    });
    unawaited(
      AnalyticsService.track(
        'tax_type_selected',
        properties: {'tax_type': option.label},
      ),
    );
    _scheduleDraftSave();
  }
}

class _SearchPickerSheet<T> extends StatefulWidget {
  const _SearchPickerSheet({
    required this.title,
    required this.items,
    required this.selectedKey,
    required this.searchText,
    required this.itemKey,
    required this.titleBuilder,
    required this.subtitleBuilder,
  });

  final String title;
  final List<T> items;
  final String? selectedKey;
  final String Function(T item) searchText;
  final String Function(T item) itemKey;
  final String Function(T item) titleBuilder;
  final String Function(T item) subtitleBuilder;

  @override
  State<_SearchPickerSheet<T>> createState() => _SearchPickerSheetState<T>();
}

class _SearchPickerSheetState<T> extends State<_SearchPickerSheet<T>> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = widget.items
        .where((item) => widget.searchText(item).contains(query))
        .toList();
    final height = MediaQuery.of(context).size.height * 0.78;

    return SafeArea(
      child: Container(
        height: height,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: const BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusXL),
          ),
          border: Border(
            top: BorderSide(color: AppTheme.glassBorder, width: 1.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary.withAlpha(80),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(widget.title, style: AppTheme.headlineMedium()),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              style: AppTheme.bodyLarge(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: AppTheme.bodyMedium(color: AppTheme.textHint),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear_rounded),
                      ),
                filled: true,
                fillColor: AppTheme.bgSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No matches found',
                        style: AppTheme.bodyMedium(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    )
                  : ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final selected =
                            widget.itemKey(item) == widget.selectedKey;
                        return ListTile(
                          minVerticalPadding: 10,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusSM,
                            ),
                          ),
                          tileColor: selected
                              ? AppTheme.emerald.withAlpha(20)
                              : AppTheme.bgSurface,
                          title: Text(
                            widget.titleBuilder(item),
                            style: AppTheme.bodyLarge(
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            widget.subtitleBuilder(item),
                            style: AppTheme.bodyMedium(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          trailing: selected
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppTheme.emerald,
                                )
                              : const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackgroundOrbs extends StatelessWidget {
  const _BackgroundOrbs();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned(
            top: -size.width * 0.3,
            right: -size.width * 0.2,
            child: Container(
              width: size.width * 0.7,
              height: size.width * 0.7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppTheme.emerald.withAlpha(20), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -size.width * 0.2,
            left: -size.width * 0.2,
            child: Container(
              width: size.width * 0.6,
              height: size.width * 0.6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.electricBlue.withAlpha(16),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
