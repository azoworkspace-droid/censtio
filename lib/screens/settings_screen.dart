import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/onboarding_options.dart';
import '../providers/business_profile_provider.dart';
import '../providers/currency_provider.dart';
import '../providers/tax_rate_provider.dart';
import '../screens/paywall_screen.dart';
import '../services/revenuecat_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_brand_icon.dart';
import '../widgets/glass_card.dart';
import '../widgets/search_picker_sheet.dart';

/// Screen for configuring user business profile, branding logo, currency, and bank details.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _taglineController = TextEditingController();
  final _addressController = TextEditingController();
  final _taxIdController = TextEditingController();
  final _bankDetailsController = TextEditingController();
  final _currencyController = TextEditingController();
  final _taxRateController = TextEditingController();

  String? _logoPath;
  String _selectedCurrencyCode = 'USD';
  String? _selectedCountryCode;
  bool _showPaymentDetailsOnInvoices = true;
  String _selectedTaxLabel = 'Tax ID';
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _taglineController.dispose();
    _addressController.dispose();
    _taxIdController.dispose();
    _bankDetailsController.dispose();
    _currencyController.dispose();
    _taxRateController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final profile = await SettingsService.getBusinessProfile();
    final currency = ref.read(currencySymbolProvider);
    final defaultTaxRate = ref.read(defaultTaxRateProvider);
    final savedCurrencyCode = await SettingsService.getCurrencyCode();
    final savedLabel = await SettingsService.getTaxIdLabel();
    final savedVal = await SettingsService.getTaxIdValue();

    if (!mounted) return;
    setState(() {
      _nameController.text = profile.name;
      _taglineController.text = profile.tagline;
      _addressController.text = profile.address ?? '';
      _selectedTaxLabel =
          onboardingTaxIds.any((option) => option.label == savedLabel)
          ? savedLabel
          : 'Other';
      _taxIdController.text = savedVal;
      _bankDetailsController.text = profile.bankDetails ?? '';
      _currencyController.text = currency;
      _selectedCurrencyCode =
          onboardingCurrencies.any((option) => option.code == savedCurrencyCode)
          ? savedCurrencyCode
          : _currencyCodeForSymbol(currency);
      _selectedCountryCode = onboardingCountries
          .where(
            (option) =>
                option.name == profile.country ||
                option.code == profile.country,
          )
          .map((option) => option.code)
          .firstOrNull;
      _taxRateController.text = defaultTaxRate.toStringAsFixed(
        defaultTaxRate.truncateToDouble() == defaultTaxRate ? 0 : 1,
      );
      _logoPath = profile.logoPath;
      _showPaymentDetailsOnInvoices = profile.showPaymentDetailsOnInvoices;
      _isLoading = false;
    });
  }

  Future<void> _pickLogo() async {
    final isPro = await RevenueCatService.isProUser();
    if (!isPro && mounted) {
      _showProLogoDialog();
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      setState(() {
        _logoPath = pickedFile.path;
      });
    }
  }

  void _showProLogoDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusXL),
            ),
            border: Border(
              top: BorderSide(color: AppTheme.glassBorder, width: 1.5),
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppBrandIcon(size: 60, borderRadius: 18, showGlow: false),
              const SizedBox(height: 16),
              Text(
                'Custom Logo is a Pro Feature',
                style: AppTheme.titleLarge(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Upload your business logo and remove invoice watermarks by upgrading to Centsio Pro.',
                style: AppTheme.bodyMedium(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.emerald,
                    foregroundColor: AppTheme.bgDeep,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                    ),
                  ),
                  icon: const Icon(Icons.star_rounded, size: 20),
                  label: Text(
                    'Upgrade to Pro — \$29.99/year',
                    style: AppTheme.bodyLarge(color: AppTheme.bgDeep),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PaywallScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _removeLogo() {
    setState(() {
      _logoPath = null;
    });
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    await SettingsService.saveBusinessProfile(
      name: _nameController.text.trim(),
      tagline: _taglineController.text.trim(),
      country: countryForCode(_selectedCountryCode)?.name,
      address: _addressController.text.trim(),
      bankDetails: _bankDetailsController.text.trim(),
      logoPath: _logoPath,
      showPaymentDetailsOnInvoices: _showPaymentDetailsOnInvoices,
    );

    await SettingsService.saveTaxIdDetails(
      _selectedTaxLabel,
      _taxIdController.text.trim(),
    );

    await ref
        .read(currencySymbolProvider.notifier)
        .setCurrency(_currencyController.text);
    await SettingsService.saveCurrencySelection(
      code: _selectedCurrencyCode,
      symbol: _currencyController.text,
    );
    await ref
        .read(currencyCodeProvider.notifier)
        .setCurrencyCode(_selectedCurrencyCode);

    final taxRateVal = double.tryParse(_taxRateController.text.trim()) ?? 0.0;
    await ref.read(defaultTaxRateProvider.notifier).setTaxRate(taxRateVal);

    await ref.read(businessProfileProvider.notifier).refresh();

    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.emerald,
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: AppTheme.bgDeep),
            const SizedBox(width: 10),
            Text(
              'Settings saved successfully!',
              style: AppTheme.bodyMedium(color: AppTheme.bgDeep),
            ),
          ],
        ),
      ),
    );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Profile', style: AppTheme.titleLarge()),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.glassBorder),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppTheme.emerald,
                strokeWidth: 2.5,
              ),
            )
          : SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _buildProfileHero(),
                    const SizedBox(height: 24),

                    _buildBusinessDetailsCard(),
                    const SizedBox(height: 24),

                    _buildCurrencyCard(),
                    const SizedBox(height: 24),

                    _buildLogoPickerCard(),
                    const SizedBox(height: 24),

                    _buildBankDetailsCard(),
                    const SizedBox(height: 32),

                    // ── Save Button ──────────────────────────────────────────
                    SizedBox(
                      height: 58,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.emerald,
                          foregroundColor: AppTheme.bgDeep,
                          elevation: 8,
                          shadowColor: AppTheme.emeraldGlow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusMD,
                            ),
                          ),
                        ),
                        onPressed: _isSaving ? null : _saveSettings,
                        child: _isSaving
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: AppTheme.bgDeep,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.save_rounded, size: 22),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Save Settings',
                                    style: AppTheme.titleLarge(
                                      color: AppTheme.bgDeep,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  // ── Section Cards ─────────────────────────────────────────────────────────

  Widget _buildProfileHero() {
    final name = _nameController.text.trim();
    final hasConfiguredName =
        name.isNotEmpty && name != BusinessProfile.defaultProfile.name;
    final initials = name.isEmpty
        ? 'F'
        : name
              .split(RegExp(r'\s+'))
              .where((part) => part.isNotEmpty)
              .take(2)
              .map((part) => part[0].toUpperCase())
              .join();
    final isReady =
        hasConfiguredName && _currencyController.text.trim().isNotEmpty;
    final hasLogo = _logoPath != null && File(_logoPath!).existsSync();

    return GlassCard(
      padding: const EdgeInsets.all(20),
      borderRadius: AppTheme.radiusXL,
      gradient: AppTheme.glassGradient,
      boxShadow: const [
        BoxShadow(
          color: AppTheme.emeraldGlow,
          blurRadius: 22,
          spreadRadius: -8,
        ),
      ],
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.emerald.withAlpha(24),
              border: Border.all(
                color: isReady ? AppTheme.emerald : AppTheme.glassBorder,
                width: 1.5,
              ),
            ),
            child: hasLogo
                ? Image.file(File(_logoPath!), fit: BoxFit.cover)
                : Center(
                    child: Text(
                      initials,
                      style: AppTheme.headlineMedium(color: AppTheme.emerald),
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name.isEmpty ? 'Your invoice profile' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.titleLarge(color: AppTheme.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _statusPill(isReady),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  isReady
                      ? 'Ready to personalize your invoices'
                      : 'Complete the essentials for a polished invoice identity',
                  style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(bool isReady) {
    final color = isReady ? AppTheme.emerald : AppTheme.warningAmber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Text(
        isReady ? 'READY' : 'SETUP',
        style: AppTheme.labelSmall(color: color),
      ),
    );
  }

  Widget _buildCurrencyCard() {
    const popularCurrencyCodes = [
      'USD',
      'EUR',
      'GBP',
      'CHF',
      'MAD',
      'CAD',
      'AUD',
      'INR',
      'JPY',
      'BRL',
      'SEK',
      'NOK',
      'DKK',
      'PLN',
    ];
    final presets = [
      for (final code in popularCurrencyCodes)
        for (final option in onboardingCurrencies)
          if (option.code == code) option,
    ];

    return GlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.emerald.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.currency_exchange_rounded,
                  color: AppTheme.emerald,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Currency & invoicing',
                      style: AppTheme.titleLarge(color: AppTheme.emerald),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Preferred currency symbol & code',
                      style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildTextField(
            controller: _currencyController,
            label: 'Preferred currency',
            hint: 'Choose a currency symbol or ISO code',
            prefixIcon: Icons.attach_money_rounded,
            validator: (v) => v == null || v.trim().isEmpty
                ? 'Currency symbol is required'
                : null,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: presets.map((preset) {
              final isSelected =
                  _selectedCurrencyCode == preset.code ||
                  (_selectedCurrencyCode == 'USD' &&
                      _currencyController.text == preset.symbol);
              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedCurrencyCode = preset.code;
                    _currencyController.text = preset.symbol;
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: isSelected ? AppTheme.emeraldGradient : null,
                    color: isSelected ? null : Colors.white.withAlpha(10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.emerald
                          : AppTheme.glassBorder,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        preset.symbol,
                        style: AppTheme.bodyLarge(
                          color: isSelected
                              ? AppTheme.bgDeep
                              : AppTheme.emerald,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        preset.code,
                        style: AppTheme.labelSmall(
                          color: isSelected
                              ? AppTheme.bgDeep
                              : AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _currencyCodeForSymbol(String symbol) {
    for (final option in onboardingCurrencies) {
      if (option.symbol == symbol) return option.code;
    }
    return 'USD';
  }

  Widget _buildCountryField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Country / region (Optional)',
          style: AppTheme.labelSmall(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 8),
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedCountryCode,
              hint: Text(
                'Select country / region',
                style: AppTheme.bodyMedium(color: AppTheme.textHint),
              ),
              dropdownColor: AppTheme.bgCard,
              isExpanded: true,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppTheme.textSecondary,
              ),
              style: AppTheme.bodyMedium(
                color: AppTheme.textPrimary,
              ).copyWith(fontWeight: FontWeight.w600),
              items: onboardingCountries.map((country) {
                return DropdownMenuItem<String>(
                  value: country.code,
                  child: Text('${country.name} · ${country.code}'),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedCountryCode = value);
              },
            ),
          ),
        ),
      ],
    );
  }

  List<TaxIdOption> get _taxOptions {
    final countryCode = _selectedCountryCode;
    final options = [...onboardingTaxIds];
    options.sort((left, right) {
      final leftSuggested =
          countryCode != null && left.countryCodes.contains(countryCode);
      final rightSuggested =
          countryCode != null && right.countryCodes.contains(countryCode);
      if (leftSuggested != rightSuggested) return leftSuggested ? -1 : 1;
      return left.label.compareTo(right.label);
    });
    return options;
  }

  Future<void> _showTaxIdPicker() async {
    final country = countryForCode(_selectedCountryCode);
    final selected = await showModalBottomSheet<TaxIdOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SearchPickerSheet<TaxIdOption>(
        title: 'Tax ID type',
        items: _taxOptions,
        selectedKey: _selectedTaxLabel,
        searchText: (item) => item.searchableText,
        itemKey: (item) => item.label,
        titleBuilder: (item) => item.label,
        subtitleBuilder: (item) {
          final isSuggested =
              country != null && item.countryCodes.contains(country.code);
          return isSuggested
              ? 'Suggested for ${country.name} · ${item.description}'
              : item.description;
        },
      ),
    );
    if (selected == null || !mounted) return;

    if (selected.label == 'SSN') {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: Text('Sensitive identifier', style: AppTheme.titleLarge()),
          content: Text(
            'Only use SSN when it is legally required for your invoices. Keep it private and share it carefully.',
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

    setState(() => _selectedTaxLabel = selected.label);
  }

  Widget _buildLogoPickerCard() {
    final hasLogo = _logoPath != null && File(_logoPath!).existsSync();

    return GlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.electricBlue.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.image_outlined,
                  color: AppTheme.electricBlue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Invoice branding',
                      style: AppTheme.titleLarge(color: AppTheme.electricBlue),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Custom logo printed on PDF headers',
                      style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              if (hasLogo)
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppTheme.errorRed,
                    size: 20,
                  ),
                  onPressed: _removeLogo,
                  tooltip: 'Remove Logo',
                ),
            ],
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: _pickLogo,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: 130,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasLogo
                      ? AppTheme.emerald.withAlpha(140)
                      : AppTheme.glassBorder,
                  width: hasLogo ? 1.5 : 1.0,
                ),
                boxShadow: hasLogo
                    ? [
                        BoxShadow(
                          color: AppTheme.emerald.withAlpha(25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: hasLogo
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.file(
                            File(_logoPath!),
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                          Positioned(
                            bottom: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(200),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppTheme.emerald.withAlpha(100),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.photo_camera_outlined,
                                    color: AppTheme.emerald,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Change Logo',
                                    style: AppTheme.labelSmall(
                                      color: AppTheme.emerald,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.emerald.withAlpha(20),
                            border: Border.all(
                              color: AppTheme.emerald.withAlpha(60),
                            ),
                          ),
                          child: const Icon(
                            Icons.add_a_photo_rounded,
                            color: AppTheme.emerald,
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Upload Custom Logo',
                          style: AppTheme.bodyLarge().copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'PNG or JPG up to 5MB (Replaces initials tile on PDFs)',
                          style: AppTheme.labelSmall(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessDetailsCard() {
    return GlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.emerald.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: AppTheme.emerald,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Business profile',
                      style: AppTheme.titleLarge(color: AppTheme.emerald),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your business details printed on client invoices',
                      style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildTextField(
            controller: _nameController,
            label: 'Business name or full name *',
            hint: 'Your name or business name',
            prefixIcon: Icons.business_rounded,
            validator: (v) => v == null || v.trim().isEmpty
                ? 'Business name is required'
                : null,
          ),
          const SizedBox(height: 16),
          _buildCountryField(),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _taglineController,
            label: 'What do you do? (Optional)',
            hint: 'Your job title or services',
            prefixIcon: Icons.work_outline_rounded,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _addressController,
            label: 'Business Address (Optional)',
            hint: 'Street, city, region, postal code',
            prefixIcon: Icons.location_on_outlined,
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tax ID type (Optional)',
                      style: AppTheme.labelSmall(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(10),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.glassBorder),
                      ),
                      child: Semantics(
                        button: true,
                        label: 'Tax ID type, $_selectedTaxLabel',
                        child: InkWell(
                          onTap: _showTaxIdPicker,
                          borderRadius: BorderRadius.circular(14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _selectedTaxLabel,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.bodyMedium(
                                    color: AppTheme.textPrimary,
                                  ).copyWith(fontWeight: FontWeight.w600),
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
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tax number (Optional)',
                      style: AppTheme.labelSmall(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 52,
                      child: TextFormField(
                        controller: _taxIdController,
                        style: AppTheme.bodyMedium(
                          color: AppTheme.textPrimary,
                        ).copyWith(fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: 'Enter your tax number',
                          hintStyle: AppTheme.bodyMedium(
                            color: AppTheme.textHint,
                          ),
                          prefixIcon: const Icon(
                            Icons.badge_outlined,
                            color: AppTheme.emerald,
                            size: 20,
                          ),
                          filled: true,
                          fillColor: Colors.white.withAlpha(10),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppTheme.glassBorder,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppTheme.emerald,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Default tax rate for new invoices (Optional)',
            style: AppTheme.labelSmall(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: TextFormField(
              controller: _taxRateController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: AppTheme.bodyMedium(
                color: AppTheme.textPrimary,
              ).copyWith(fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Leave blank for no tax',
                hintStyle: AppTheme.bodyMedium(color: AppTheme.textHint),
                prefixIcon: const Icon(
                  Icons.percent_outlined,
                  color: AppTheme.emerald,
                  size: 20,
                ),
                filled: true,
                fillColor: Colors.white.withAlpha(10),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.glassBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: AppTheme.emerald,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Used as the default for new invoices. You can change it later.',
            style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'Tax calculations are estimates and are not tax advice.',
            style: AppTheme.labelSmall(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [0, 5, 10, 20].map((rate) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () {
                      _taxRateController.text = rate.toString();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.glassBorder),
                      ),
                      child: Text(
                        '$rate%',
                        style: AppTheme.bodyMedium(color: AppTheme.textPrimary),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBankDetailsCard() {
    return GlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.warningAmber.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.account_balance_outlined,
                  color: AppTheme.warningAmber,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment details',
                      style: AppTheme.titleLarge(color: AppTheme.warningAmber),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Printed at the bottom of client PDF invoices',
                      style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Show on invoices',
              style: AppTheme.bodyLarge(color: AppTheme.textPrimary),
            ),
            subtitle: Text(
              'Let clients see these details at the bottom of your PDFs.',
              style: AppTheme.bodyMedium(color: AppTheme.textSecondary),
            ),
            value: _showPaymentDetailsOnInvoices,
            activeThumbColor: AppTheme.emerald,
            onChanged: (value) =>
                setState(() => _showPaymentDetailsOnInvoices = value),
          ),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _bankDetailsController,
            label: 'Payment details',
            hint:
                'Bank name, account holder, IBAN, routing number, or payment link',
            prefixIcon: Icons.account_balance_wallet_outlined,
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? prefixIcon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      style: AppTheme.bodyMedium(
        color: AppTheme.textPrimary,
      ).copyWith(fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTheme.bodyMedium(color: AppTheme.textSecondary),
        hintText: hint,
        hintStyle: AppTheme.bodyMedium(color: AppTheme.textHint),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: AppTheme.emerald, size: 20)
            : null,
        filled: true,
        fillColor: Colors.white.withAlpha(10),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.emerald, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.errorRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.errorRed, width: 1.5),
        ),
      ),
    );
  }
}
