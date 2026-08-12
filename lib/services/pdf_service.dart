import 'dart:io';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/invoice.dart';
import '../services/app_database.dart';
import '../services/revenuecat_service.dart';
import '../services/settings_service.dart';

/// Generates a beautifully formatted A4 PDF invoice customized with
/// user business profile branding, logo, multi-language support, and
/// premium invoice templates ('Basic', 'Modern', 'Elite').
class PdfService {
  PdfService._();

  // ── Brand palette ──────────────────────────────────────────────────────────

  static const PdfColor _accentEmerald = PdfColor.fromInt(0xFF00C896);
  static const PdfColor _textDark = PdfColor.fromInt(0xFF111827);
  static const PdfColor _textMuted = PdfColor.fromInt(0xFF6B7280);
  static const PdfColor _bgLight = PdfColor.fromInt(0xFFF9FAFB);
  static const PdfColor _borderGrey = PdfColor.fromInt(0xFFE5E7EB);
  static const PdfColor _headerFill = PdfColor.fromInt(0xFF111827);
  static const PdfColor _white = PdfColors.white;

  // ── Translation dictionary ────────────────────────────────────────────────

  static final Map<String, Map<String, String>> translations = {
    'English': {
      'invoice': 'INVOICE',
      'quote': 'QUOTE',
      'bill_to': 'BILL TO',
      'invoice_details': 'INVOICE DETAILS',
      'inv_no': 'Invoice No.',
      'date': 'Date',
      'status': 'Status',
      'tax_rate': 'Tax Rate',
      'desc': 'DESCRIPTION',
      'qty': 'QTY',
      'price': 'UNIT PRICE',
      'total': 'TOTAL',
      'subtotal': 'Subtotal',
      'tax': 'Tax',
      'grand_total': 'GRAND TOTAL',
      'notes': 'NOTES',
      'thanks': 'Thank you for your business!',
      'issued_by': 'Issued by',
      'page': 'Page',
      'payment_details': 'PAYMENT DETAILS',
      'payment': 'Payment Method',
    },
    'Français': {
      'invoice': 'FACTURE',
      'quote': 'DEVIS',
      'bill_to': 'FACTURÉ À',
      'invoice_details': 'DÉTAILS FACTURE',
      'inv_no': 'N° Facture',
      'date': 'Date',
      'status': 'Statut',
      'tax_rate': 'Taux de taxe',
      'desc': 'DESCRIPTION',
      'qty': 'QTÉ',
      'price': 'PRIX UNITAIRE',
      'total': 'TOTAL',
      'subtotal': 'Sous-total',
      'tax': 'Taxe',
      'grand_total': 'TOTAL GÉNÉRAL',
      'notes': 'NOTES',
      'thanks': 'Merci pour votre confiance !',
      'issued_by': 'Émis par',
      'page': 'Page',
      'payment_details': 'DÉTAILS DE PAIEMENT (RIB / IBAN)',
      'payment': 'Méthode de paiement',
    },
    'Español': {
      'invoice': 'FACTURA',
      'quote': 'PRESUPUESTO',
      'bill_to': 'FACTURAR A',
      'invoice_details': 'DETALLES FACTURA',
      'inv_no': 'Nº Factura',
      'date': 'Fecha',
      'status': 'Estado',
      'tax_rate': 'Tasa de imp.',
      'desc': 'DESCRIPCIÓN',
      'qty': 'CANT',
      'price': 'PRECIO UNIT.',
      'total': 'TOTAL',
      'subtotal': 'Subtotal',
      'tax': 'Impuesto',
      'grand_total': 'TOTAL GENERAL',
      'notes': 'NOTAS',
      'thanks': '¡Gracias por su negocio!',
      'issued_by': 'Emitido por',
      'page': 'Página',
      'payment_details': 'DETALLES DE PAGO (RIB / IBAN)',
      'payment': 'Método de pago',
    },
  };

  // ── Tax label helper ───────────────────────────────────────────────────────

  static String _getTaxLabel(String? country) {
    if (country == null || country.trim().isEmpty) return 'Tax ID';
    final c = country.trim().toLowerCase();
    if (c == 'morocco' || c == 'maroc' || c == 'ma') return 'ICE';
    if (c == 'usa' || c == 'us' || c == 'united states') return 'EIN';
    if (c == 'uk' || c == 'united kingdom' || c == 'gb') return 'UTR';
    if (c == 'france' ||
        c == 'spain' ||
        c == 'germany' ||
        c == 'italy' ||
        c == 'fr' ||
        c == 'es' ||
        c == 'de' ||
        c == 'it') {
      return 'VAT';
    }
    return 'Tax ID';
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Builds and returns the raw PDF bytes for [invoice].
  static Future<List<int>> generateInvoicePdf({
    required Invoice invoice,
    required Client client,
    required List<InvoiceItem> items,
    String? templateType,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    final profile = await SettingsService.getBusinessProfile();
    final isPro = await RevenueCatService.isProUser();
    final currencySymbol = await SettingsService.getCurrencySymbol();
    final currencyCode = await SettingsService.getCurrencyCode();

    // Load Google Fonts to support international currency symbols
    final robotoRegular = await PdfGoogleFonts.robotoRegular();
    final robotoBold = await PdfGoogleFonts.robotoBold();
    final pdfCurrencySymbol =
        robotoRegular is pw.TtfFont && robotoBold is pw.TtfFont
        ? currencySymbol
        : _asciiSafeCurrencySymbol(currencySymbol, currencyCode);

    pw.MemoryImage? logoImage;
    // Only load custom logo for Pro users
    if (isPro && profile.logoPath != null) {
      final logoFile = File(profile.logoPath!);
      if (logoFile.existsSync()) {
        try {
          final bytes = logoFile.readAsBytesSync();
          logoImage = pw.MemoryImage(bytes);
        } catch (_) {
          logoImage = null;
        }
      }
    }

    final doc = pw.Document(
      title: '${invoice.invoiceNumber} - ${profile.name}',
      author: profile.name,
      theme: pw.ThemeData.withFont(base: robotoRegular, bold: robotoBold),
    );

    final template = templateType ?? invoice.template ?? 'Classic';
    if (template == 'Modern' || template == 'Elite') {
      final t = _premiumTranslationsFor(invoice);
      doc.addPage(
        pw.MultiPage(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.fromLTRB(42, 34, 42, 38),
          header: (context) =>
              _premiumRunningHeader(context, profile, invoice, t, template),
          footer: (context) => _premiumFooter(context, t),
          build: (context) => template == 'Modern'
              ? _buildModernPremiumSections(
                  context,
                  invoice,
                  client,
                  items,
                  profile,
                  logoImage,
                  isPro,
                  pdfCurrencySymbol,
                  currencyCode,
                  t,
                )
              : _buildElitePremiumSections(
                  context,
                  invoice,
                  client,
                  items,
                  profile,
                  logoImage,
                  isPro,
                  pdfCurrencySymbol,
                  currencyCode,
                  t,
                ),
        ),
      );
    } else {
      // Basic keeps its existing single-page layout unchanged.
      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 48),
          build: (context) => _buildPage(
            context,
            invoice,
            client,
            items,
            profile,
            logoImage,
            isPro,
            pdfCurrencySymbol,
            templateType,
          ),
        ),
      );
    }

    return doc.save();
  }

  // ── Template Router ────────────────────────────────────────────────────────

  static Map<String, String> _translationFor(Invoice invoice) {
    final baseT = translations[invoice.language] ?? translations['English']!;
    final t = Map<String, String>.from(baseT);

    if (invoice.documentType == 'quote') {
      t['invoice'] = t['quote'] ?? 'QUOTE';
      t['inv_no'] = invoice.language == 'Français'
          ? 'N° Devis'
          : (invoice.language == 'Español' ? 'Nº Presupuesto' : 'Quote No.');
      t['invoice_details'] = invoice.language == 'Français'
          ? 'DÉTAILS DEVIS'
          : (invoice.language == 'Español'
                ? 'DETALLES PRESUPUESTO'
                : 'QUOTE DETAILS');
    }
    return t;
  }

  static Map<String, String> _premiumTranslationsFor(Invoice invoice) {
    final t = _translationFor(invoice);
    // Modern and Elite must use a global, payment-method-neutral label.
    t['payment_details'] = switch (invoice.language) {
      'Français' => 'DÉTAILS DE PAIEMENT',
      'Español' => 'DETALLES DE PAGO',
      _ => 'PAYMENT DETAILS',
    };
    return t;
  }

  static pw.Widget _buildPage(
    pw.Context context,
    Invoice invoice,
    Client client,
    List<InvoiceItem> items,
    BusinessProfile profile,
    pw.MemoryImage? logoImage,
    bool isPro,
    String currencySymbol,
    String? templateType,
  ) {
    final t = _translationFor(invoice);
    final template = templateType ?? invoice.template ?? 'Classic';

    switch (template) {
      case 'Modern':
        return _buildModernTemplate(
          context,
          invoice,
          client,
          items,
          profile,
          logoImage,
          isPro,
          currencySymbol,
          t,
        );
      case 'Elite':
        return _buildEliteTemplate(
          context,
          invoice,
          client,
          items,
          profile,
          logoImage,
          isPro,
          currencySymbol,
          t,
        );
      case 'Classic':
      case 'Basic':
      default:
        return _buildBasicTemplate(
          context,
          invoice,
          client,
          items,
          profile,
          logoImage,
          isPro,
          currencySymbol,
          t,
        );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. BASIC TEMPLATE (Clean Standard Layout)
  // ═══════════════════════════════════════════════════════════════════════════

  static pw.Widget _buildBasicTemplate(
    pw.Context context,
    Invoice invoice,
    Client client,
    List<InvoiceItem> items,
    BusinessProfile profile,
    pw.MemoryImage? logoImage,
    bool isPro,
    String currencySymbol,
    Map<String, String> t,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _header(invoice, profile, logoImage, t),
        pw.SizedBox(height: 32),
        _billingRow(invoice, client, profile, t),
        pw.SizedBox(height: 28),
        _itemsTable(items, currencySymbol, t),
        pw.SizedBox(height: 20),
        _totalsSection(invoice, items, currencySymbol, t),
        if (profile.showPaymentDetailsOnInvoices &&
            profile.bankDetails != null &&
            profile.bankDetails!.isNotEmpty) ...[
          pw.SizedBox(height: 20),
          _bankDetailsSection(profile, t),
        ],
        pw.Spacer(),
        _footer(invoice, profile, isPro, t),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. MODERN TEMPLATE — Blue-Purple Gradient Theme with Bold Typography
  // ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. MODERN TEMPLATE — Light Mint & Deep Teal Theme (Fresh & Professional)
  // ═══════════════════════════════════════════════════════════════════════════

  static const PdfColor _modernTeal = PdfColor.fromInt(0xFF0F766E); // Deep Teal
  static const PdfColor _modernTealLight = PdfColor.fromInt(
    0xFFCCFBF1,
  ); // Mint Tint
  static const PdfColor _modernTealBorder = PdfColor.fromInt(
    0xFF99F6E4,
  ); // Soft Border
  static const PdfColor _modernBannerBg = PdfColor.fromInt(
    0xFFF0FDF4,
  ); // Light Fresh Green/Teal

  static pw.Widget _buildModernTemplate(
    pw.Context context,
    Invoice invoice,
    Client client,
    List<InvoiceItem> items,
    BusinessProfile profile,
    pw.MemoryImage? logoImage,
    bool isPro,
    String currencySymbol,
    Map<String, String> t,
  ) {
    final firstLetter = profile.name.trim().isNotEmpty
        ? profile.name.trim()[0].toUpperCase()
        : 'F';
    final subtotal = items.fold<double>(
      0,
      (s, i) => s + i.unitPrice * i.quantity,
    );
    final taxAmount = subtotal * (invoice.taxRate / 100);
    final grandTotal = subtotal + taxAmount;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // ── Fresh Light Header Banner ──────────────────────────────────
        pw.Container(
          padding: const pw.EdgeInsets.all(20),
          decoration: pw.BoxDecoration(
            color: _modernBannerBg,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
            border: pw.Border.all(color: _modernTealBorder, width: 1),
          ),
          child: pw.Row(
            children: [
              // Logo / Initial Badge
              if (logoImage != null)
                pw.Container(
                  width: 56,
                  height: 56,
                  decoration: pw.BoxDecoration(
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(10),
                    ),
                    color: _white,
                    border: pw.Border.all(color: _modernTealBorder, width: 1),
                    image: pw.DecorationImage(
                      image: logoImage,
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                )
              else
                pw.Container(
                  width: 56,
                  height: 56,
                  decoration: const pw.BoxDecoration(
                    color: _modernTeal,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      firstLetter,
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: _white,
                      ),
                    ),
                  ),
                ),
              pw.SizedBox(width: 14),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    profile.name,
                    style: pw.TextStyle(
                      fontSize: 17,
                      fontWeight: pw.FontWeight.bold,
                      color: _textDark,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    profile.tagline,
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      color: _modernTeal,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (profile.taxId != null && profile.taxId!.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      profile.taxId!.contains(':')
                          ? profile.taxId!
                          : 'Tax ID: ${profile.taxId!}',
                      style: const pw.TextStyle(
                        fontSize: 8.5,
                        color: _textMuted,
                      ),
                    ),
                  ],
                ],
              ),
              pw.Spacer(),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    t['invoice']!,
                    style: pw.TextStyle(
                      fontSize: 26,
                      fontWeight: pw.FontWeight.bold,
                      color: _modernTeal,
                      letterSpacing: 2,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  // High contrast invoice number badge
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: const pw.BoxDecoration(
                      color: _modernTeal,
                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                    ),
                    child: pw.Text(
                      invoice.invoiceNumber,
                      style: pw.TextStyle(
                        fontSize: 10.5,
                        fontWeight: pw.FontWeight.bold,
                        color: _white,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    '${t['date']!}: ${_formatDate(invoice.date)}',
                    style: const pw.TextStyle(fontSize: 9, color: _textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),

        pw.SizedBox(height: 20),

        // ── Bill To + Invoice Details row ─────────────────────────────────
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color: _modernTealLight,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
            border: pw.Border.all(color: _modernTealBorder, width: 0.8),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      t['bill_to']!,
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: _modernTeal,
                        letterSpacing: 1,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      client.name,
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: _textDark,
                      ),
                    ),
                    if (client.address != null) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        client.address!,
                        style: pw.TextStyle(fontSize: 9.5, color: _textMuted),
                      ),
                    ],
                    if (client.country != null &&
                        client.country!.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Country: ${client.country!}',
                        style: pw.TextStyle(fontSize: 9.5, color: _textMuted),
                      ),
                    ],
                    if (client.taxId != null && client.taxId!.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        client.taxId!.contains(':')
                            ? client.taxId!
                            : '${_getTaxLabel(client.country)}: ${client.taxId!}',
                        style: pw.TextStyle(fontSize: 9.5, color: _textMuted),
                      ),
                    ],
                    if (client.phone != null) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        client.phone!,
                        style: pw.TextStyle(fontSize: 9.5, color: _textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              pw.Container(width: 0.8, height: 70, color: _modernTealBorder),
              pw.SizedBox(width: 18),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    t['invoice_details']!,
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: _modernTeal,
                      letterSpacing: 1,
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  _detailRow(t['inv_no']!, invoice.invoiceNumber),
                  pw.SizedBox(height: 3),
                  _detailRow(t['date']!, _formatDate(invoice.date)),
                  pw.SizedBox(height: 3),
                  _detailRow(
                    t['tax_rate']!,
                    '${invoice.taxRate.toStringAsFixed(1)}%',
                  ),
                  pw.SizedBox(height: 3),
                  _detailRow(
                    t['payment'] ?? 'Payment',
                    invoice.paymentMethod ?? 'Bank Transfer',
                  ),
                ],
              ),
            ],
          ),
        ),

        pw.SizedBox(height: 20),

        // ── Items Table with Teal Header ─────────────────────────────────
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(3.5),
            1: pw.FlexColumnWidth(1.0),
            2: pw.FlexColumnWidth(1.5),
            3: pw.FlexColumnWidth(1.5),
          },
          border: pw.TableBorder.all(color: _modernTealBorder, width: 0.5),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _modernTeal),
              children: [
                _tableHeader(t['desc']!),
                _tableHeader(t['qty']!, align: pw.TextAlign.center),
                _tableHeader(t['price']!, align: pw.TextAlign.right),
                _tableHeader(t['total']!, align: pw.TextAlign.right),
              ],
            ),
            ...items.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final rowTotal = item.unitPrice * item.quantity;
              return pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: idx.isEven ? _white : _modernTealLight,
                ),
                children: [
                  _tableCell(item.description),
                  _tableCell(
                    item.quantity.toString(),
                    align: pw.TextAlign.center,
                  ),
                  _tableCell(
                    '$currencySymbol${item.unitPrice.toStringAsFixed(2)}',
                    align: pw.TextAlign.right,
                  ),
                  _tableCell(
                    '$currencySymbol${rowTotal.toStringAsFixed(2)}',
                    align: pw.TextAlign.right,
                    bold: true,
                  ),
                ],
              );
            }),
          ],
        ),

        pw.SizedBox(height: 18),

        // ── Totals with Teal Total Bar ────────────────────────────────────
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Spacer(),
            pw.SizedBox(
              width: 200,
              child: pw.Column(
                children: [
                  _totalRow(
                    t['subtotal']!,
                    '$currencySymbol${subtotal.toStringAsFixed(2)}',
                  ),
                  pw.SizedBox(height: 4),
                  if (invoice.taxRate > 0) ...[
                    _totalRow(
                      '${t['tax']!} (${invoice.taxRate.toStringAsFixed(1)}%)',
                      '$currencySymbol${taxAmount.toStringAsFixed(2)}',
                    ),
                    pw.SizedBox(height: 4),
                  ],
                  pw.Divider(color: _modernTealBorder, height: 14),
                  // Solid Teal Total Bar
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: const pw.BoxDecoration(
                      color: _modernTeal,
                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          t['grand_total']!,
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: _white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        pw.Text(
                          '$currencySymbol${grandTotal.toStringAsFixed(2)}',
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: _white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        if (profile.showPaymentDetailsOnInvoices &&
            profile.bankDetails != null &&
            profile.bankDetails!.isNotEmpty) ...[
          pw.SizedBox(height: 20),
          _bankDetailsSection(profile, t),
        ],
        pw.Spacer(),
        _footer(invoice, profile, isPro, t),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. ELITE TEMPLATE — Executive Dark Sidebar & High-End Luxury Layout
  // ═══════════════════════════════════════════════════════════════════════════

  static const PdfColor _eliteNavy = PdfColor.fromInt(0xFF0F172A);
  static const PdfColor _eliteSlate = PdfColor.fromInt(0xFF1E293B);
  static const PdfColor _eliteGold = PdfColor.fromInt(0xFFF59E0B);
  static const PdfColor _eliteLightBg = PdfColor.fromInt(0xFFF8FAFC);
  static const PdfColor _eliteBorder = PdfColor.fromInt(0xFFE2E8F0);

  static pw.Widget _buildEliteTemplate(
    pw.Context context,
    Invoice invoice,
    Client client,
    List<InvoiceItem> items,
    BusinessProfile profile,
    pw.MemoryImage? logoImage,
    bool isPro,
    String currencySymbol,
    Map<String, String> t,
  ) {
    final firstLetter = profile.name.trim().isNotEmpty
        ? profile.name.trim()[0].toUpperCase()
        : 'F';

    final subtotal = items.fold<double>(
      0,
      (s, i) => s + i.unitPrice * i.quantity,
    );
    final taxAmount = subtotal * (invoice.taxRate / 100);
    final grandTotal = subtotal + taxAmount;

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // ── Executive Left Sidebar Panel ──────────────────────────────────
        pw.Container(
          width: 170,
          padding: const pw.EdgeInsets.all(18),
          decoration: const pw.BoxDecoration(
            color: _eliteNavy,
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(14)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Logo or Gold Initial
              if (logoImage != null)
                pw.Container(
                  width: 52,
                  height: 52,
                  decoration: pw.BoxDecoration(
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(10),
                    ),
                    color: _white,
                    image: pw.DecorationImage(
                      image: logoImage,
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                )
              else
                pw.Container(
                  width: 52,
                  height: 52,
                  decoration: const pw.BoxDecoration(
                    color: _eliteGold,
                    shape: pw.BoxShape.circle,
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      firstLetter,
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: _eliteNavy,
                      ),
                    ),
                  ),
                ),
              pw.SizedBox(height: 14),

              // Business Info
              pw.Text(
                profile.name,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: _white,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                profile.tagline,
                style: const pw.TextStyle(fontSize: 8.5, color: _eliteGold),
              ),
              if (profile.taxId != null && profile.taxId!.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text(
                  profile.taxId!.contains(':')
                      ? profile.taxId!
                      : 'Tax ID: ${profile.taxId!}',
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    color: PdfColor.fromInt(0x99FFFFFF),
                  ),
                ),
              ],

              pw.SizedBox(height: 16),
              pw.Container(height: 0.5, color: PdfColor.fromInt(0x33FFFFFF)),
              pw.SizedBox(height: 16),

              // Invoice Number Badge
              pw.Text(
                t['invoice']!,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: _eliteGold,
                  letterSpacing: 2,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                invoice.invoiceNumber,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: _white,
                ),
              ),

              pw.SizedBox(height: 14),

              // Date & Status
              pw.Text(
                t['date']!,
                style: pw.TextStyle(
                  fontSize: 7.5,
                  color: PdfColor.fromInt(0x88FFFFFF),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                _formatDate(invoice.date),
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: _white,
                ),
              ),

              if (profile.showPaymentDetailsOnInvoices &&
                  profile.bankDetails != null &&
                  profile.bankDetails!.isNotEmpty) ...[
                pw.SizedBox(height: 18),
                pw.Container(height: 0.5, color: PdfColor.fromInt(0x33FFFFFF)),
                pw.SizedBox(height: 14),
                pw.Text(
                  t['payment_details']!,
                  style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                    color: _eliteGold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  profile.bankDetails!,
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    color: PdfColor.fromInt(0xCCFFFFFF),
                    height: 1.3,
                  ),
                ),
              ],

              pw.Spacer(),

              // Footer Note inside Sidebar
              pw.Text(
                (invoice.notes != null && invoice.notes!.trim().isNotEmpty)
                    ? invoice.notes!.trim()
                    : t['thanks']!,
                style: pw.TextStyle(
                  fontSize: 7.5,
                  fontStyle: pw.FontStyle.italic,
                  color: PdfColor.fromInt(0x99FFFFFF),
                ),
              ),
            ],
          ),
        ),

        pw.SizedBox(width: 20),

        // ── Main Content Area ──────────────────────────────────────────────
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Bill To Box (Executive Style)
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: _eliteLightBg,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(10),
                  ),
                  border: pw.Border.all(color: _eliteBorder, width: 0.8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          t['bill_to']!,
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: _eliteGold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          client.name,
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: _eliteNavy,
                          ),
                        ),
                        if (client.address != null) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(
                            client.address!,
                            style: pw.TextStyle(fontSize: 9, color: _textMuted),
                          ),
                        ],
                        if (client.country != null &&
                            client.country!.isNotEmpty) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Country: ${client.country!}',
                            style: pw.TextStyle(fontSize: 9, color: _textMuted),
                          ),
                        ],
                        if (client.taxId != null &&
                            client.taxId!.isNotEmpty) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(
                            client.taxId!.contains(':')
                                ? client.taxId!
                                : '${_getTaxLabel(client.country)}: ${client.taxId!}',
                            style: pw.TextStyle(fontSize: 9, color: _textMuted),
                          ),
                        ],
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          t['invoice_details']!,
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: _textMuted,
                            letterSpacing: 1,
                          ),
                        ),
                        pw.SizedBox(height: 5),
                        _detailRow(
                          t['tax_rate']!,
                          '${invoice.taxRate.toStringAsFixed(1)}%',
                        ),
                        pw.SizedBox(height: 3),
                        _detailRow(
                          t['payment'] ?? 'Payment',
                          invoice.paymentMethod ?? 'Bank Transfer',
                        ),
                        pw.SizedBox(height: 3),
                        _detailRow('Items', items.length.toString()),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 20),

              // Executive Items Table
              pw.Table(
                columnWidths: const {
                  0: pw.FlexColumnWidth(3.0),
                  1: pw.FlexColumnWidth(0.8),
                  2: pw.FlexColumnWidth(1.8),
                  3: pw.FlexColumnWidth(1.8),
                },
                border: pw.TableBorder.all(color: _eliteBorder, width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: _eliteSlate),
                    children: [
                      _tableHeader(t['desc']!),
                      _tableHeader(t['qty']!, align: pw.TextAlign.center),
                      _tableHeader(t['price']!, align: pw.TextAlign.right),
                      _tableHeader(t['total']!, align: pw.TextAlign.right),
                    ],
                  ),
                  ...items.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;
                    final rowTotal = item.unitPrice * item.quantity;
                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: idx.isEven ? _white : _eliteLightBg,
                      ),
                      children: [
                        _tableCell(item.description),
                        _tableCell(
                          item.quantity.toString(),
                          align: pw.TextAlign.center,
                        ),
                        _tableCell(
                          '$currencySymbol${item.unitPrice.toStringAsFixed(2)}',
                          align: pw.TextAlign.right,
                        ),
                        _tableCell(
                          '$currencySymbol${rowTotal.toStringAsFixed(2)}',
                          align: pw.TextAlign.right,
                          bold: true,
                        ),
                      ],
                    );
                  }),
                ],
              ),

              pw.SizedBox(height: 20),

              // Executive Grand Total Card
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: const pw.BoxDecoration(
                  color: _eliteNavy,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            t['grand_total']!,
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: _eliteGold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            'Subtotal: $currencySymbol${subtotal.toStringAsFixed(2)}  |  Tax (${invoice.taxRate.toStringAsFixed(1)}%): $currencySymbol${taxAmount.toStringAsFixed(2)}',
                            style: const pw.TextStyle(
                              fontSize: 7.5,
                              color: _white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Text(
                      '$currencySymbol${grandTotal.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: _white,
                      ),
                    ),
                  ],
                ),
              ),

              pw.Spacer(),

              // Simple Bottom Watermark
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text(
                    isPro
                        ? '${t['issued_by']!} ${profile.name}'
                        : 'Generated by Centsio AI: Invoice Maker',
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: isPro ? _textMuted : _accentEmerald,
                      fontWeight: isPro
                          ? pw.FontWeight.normal
                          : pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Responsive premium templates
  //
  // These sections intentionally live beside the legacy implementations above
  // so existing Basic invoices remain byte-for-byte on the same rendering
  // path. Modern and Elite use MultiPage, repeat their table header, and keep
  // totals/payment information in bounded blocks.
  // ═══════════════════════════════════════════════════════════════════════════

  static List<pw.Widget> _buildModernPremiumSections(
    pw.Context context,
    Invoice invoice,
    Client client,
    List<InvoiceItem> items,
    BusinessProfile profile,
    pw.MemoryImage? logoImage,
    bool isPro,
    String currencySymbol,
    String currencyCode,
    Map<String, String> t,
  ) {
    final taxRate = invoice.taxRate.clamp(0, 100).toDouble();
    final subtotal = _subtotal(items);
    final taxAmount = subtotal * taxRate / 100;
    final grandTotal = subtotal + taxAmount;
    final paymentDetails = profile.showPaymentDetailsOnInvoices
        ? _clean(profile.bankDetails)
        : null;
    final notes = _clean(invoice.notes);
    final paymentMethod = _clean(invoice.paymentMethod);

    return [
      _modernPremiumHeader(invoice, profile, logoImage, t),
      pw.SizedBox(height: 18),
      _premiumClientAndMeta(
        invoice,
        client,
        t,
        accent: _modernTeal,
        cardColor: _modernTealLight,
        borderColor: _modernTealBorder,
        language: invoice.language,
        paymentMethod: paymentMethod,
        taxRate: taxRate,
      ),
      pw.SizedBox(height: 18),
      _premiumItemsTable(
        items,
        currencySymbol,
        currencyCode,
        invoice.language,
        taxRate,
        headerColor: _modernTeal,
        alternateColor: _modernTealLight,
        borderColor: _modernTealBorder,
        t: t,
      ),
      pw.SizedBox(height: 18),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: _premiumSupportingInfo(
              paymentDetails: paymentDetails,
              paymentMethod: paymentMethod,
              notes: notes,
              t: t,
              accent: _modernTeal,
              cardColor: _bgLight,
              borderColor: _modernTealBorder,
            ),
          ),
          pw.SizedBox(width: 18),
          pw.SizedBox(
            width: 218,
            child: _premiumTotals(
              subtotal: subtotal,
              taxRate: taxRate,
              taxAmount: taxAmount,
              grandTotal: grandTotal,
              currencySymbol: currencySymbol,
              currencyCode: currencyCode,
              language: invoice.language,
              t: t,
              accent: _modernTeal,
              cardColor: _modernTeal,
              valueColor: _white,
              borderColor: _modernTealBorder,
              totalLabelColor: _white,
            ),
          ),
        ],
      ),
      if (isPro || profile.name.trim().isNotEmpty) ...[
        pw.SizedBox(height: 22),
        _premiumIssuedBy(profile, isPro, accent: _modernTeal, t: t),
      ],
    ];
  }

  static List<pw.Widget> _buildElitePremiumSections(
    pw.Context context,
    Invoice invoice,
    Client client,
    List<InvoiceItem> items,
    BusinessProfile profile,
    pw.MemoryImage? logoImage,
    bool isPro,
    String currencySymbol,
    String currencyCode,
    Map<String, String> t,
  ) {
    final taxRate = invoice.taxRate.clamp(0, 100).toDouble();
    final subtotal = _subtotal(items);
    final taxAmount = subtotal * taxRate / 100;
    final grandTotal = subtotal + taxAmount;
    final paymentDetails = profile.showPaymentDetailsOnInvoices
        ? _clean(profile.bankDetails)
        : null;
    final notes = _clean(invoice.notes);
    final paymentMethod = _clean(invoice.paymentMethod);

    return [
      _elitePremiumHeader(invoice, profile, logoImage, t),
      pw.SizedBox(height: 18),
      _premiumClientAndMeta(
        invoice,
        client,
        t,
        accent: _eliteGold,
        cardColor: _eliteLightBg,
        borderColor: _eliteBorder,
        language: invoice.language,
        paymentMethod: paymentMethod,
        taxRate: taxRate,
        strongAccent: _eliteNavy,
      ),
      pw.SizedBox(height: 18),
      _premiumItemsTable(
        items,
        currencySymbol,
        currencyCode,
        invoice.language,
        taxRate,
        headerColor: _eliteNavy,
        alternateColor: _eliteLightBg,
        borderColor: _eliteBorder,
        t: t,
      ),
      pw.SizedBox(height: 18),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: _premiumSupportingInfo(
              paymentDetails: paymentDetails,
              paymentMethod: paymentMethod,
              notes: notes,
              t: t,
              accent: _eliteGold,
              cardColor: _eliteLightBg,
              borderColor: _eliteBorder,
            ),
          ),
          pw.SizedBox(width: 18),
          pw.SizedBox(
            width: 218,
            child: _premiumTotals(
              subtotal: subtotal,
              taxRate: taxRate,
              taxAmount: taxAmount,
              grandTotal: grandTotal,
              currencySymbol: currencySymbol,
              currencyCode: currencyCode,
              language: invoice.language,
              t: t,
              accent: _eliteGold,
              cardColor: _eliteNavy,
              valueColor: _white,
              borderColor: _eliteNavy,
              totalLabelColor: _eliteGold,
            ),
          ),
        ],
      ),
      if (isPro || profile.name.trim().isNotEmpty) ...[
        pw.SizedBox(height: 22),
        _premiumIssuedBy(profile, isPro, accent: _eliteGold, t: t),
      ],
    ];
  }

  static pw.Widget _modernPremiumHeader(
    Invoice invoice,
    BusinessProfile profile,
    pw.MemoryImage? logoImage,
    Map<String, String> t,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: const pw.BoxDecoration(
        color: _modernTeal,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _premiumLogo(
                  logoImage,
                  profile.name,
                  fallbackColor: _modernTealLight,
                  fallbackTextColor: _modernTeal,
                ),
                pw.SizedBox(width: 14),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        profile.name,
                        style: pw.TextStyle(
                          fontSize: 17,
                          fontWeight: pw.FontWeight.bold,
                          color: _white,
                        ),
                      ),
                      if (_clean(profile.tagline) != null) ...[
                        pw.SizedBox(height: 3),
                        pw.Text(
                          profile.tagline,
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: _modernTealLight,
                          ),
                        ),
                      ],
                      if (_clean(profile.address) != null) ...[
                        pw.SizedBox(height: 4),
                        pw.Text(
                          profile.address!,
                          style: const pw.TextStyle(
                            fontSize: 8.5,
                            color: _white,
                          ),
                        ),
                      ],
                      if (_clean(profile.taxId) != null) ...[
                        pw.SizedBox(height: 3),
                        pw.Text(
                          profile.taxId!,
                          style: const pw.TextStyle(
                            fontSize: 8,
                            color: _modernTealLight,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          pw.SizedBox(
            width: 142,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  t['invoice']!,
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: 23,
                    fontWeight: pw.FontWeight.bold,
                    color: _white,
                    letterSpacing: 1.5,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: const pw.BoxDecoration(
                    color: _modernTealLight,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  child: pw.Text(
                    invoice.invoiceNumber,
                    textAlign: pw.TextAlign.right,
                    style: const pw.TextStyle(
                      fontSize: 9.5,
                      color: _modernTeal,
                    ),
                  ),
                ),
                pw.SizedBox(height: 7),
                _premiumHeaderMeta(
                  t['date']!,
                  _formatLocalizedDate(invoice.date, invoice.language),
                  color: _modernTealLight,
                ),
                if (invoice.status != InvoiceStatus.none) ...[
                  pw.SizedBox(height: 3),
                  _premiumHeaderMeta(
                    t['status']!,
                    invoice.status.displayName,
                    color: _modernTealLight,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _elitePremiumHeader(
    Invoice invoice,
    BusinessProfile profile,
    pw.MemoryImage? logoImage,
    Map<String, String> t,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 158,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: const pw.BoxDecoration(
              color: _eliteNavy,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _premiumLogo(
                  logoImage,
                  profile.name,
                  fallbackColor: _eliteGold,
                  fallbackTextColor: _eliteNavy,
                  circleFallback: true,
                ),
                pw.SizedBox(height: 12),
                pw.Text(
                  profile.name,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: _white,
                  ),
                ),
                if (_clean(profile.tagline) != null) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(
                    profile.tagline,
                    style: const pw.TextStyle(fontSize: 8, color: _eliteGold),
                  ),
                ],
                if (_clean(profile.address) != null) ...[
                  pw.SizedBox(height: 8),
                  pw.Text(
                    profile.address!,
                    style: const pw.TextStyle(fontSize: 7.5, color: _white),
                  ),
                ],
                if (_clean(profile.taxId) != null) ...[
                  pw.SizedBox(height: 5),
                  pw.Text(
                    profile.taxId!,
                    style: const pw.TextStyle(fontSize: 7.5, color: _eliteGold),
                  ),
                ],
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 14),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(18),
            decoration: pw.BoxDecoration(
              color: _eliteLightBg,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
              border: pw.Border.all(color: _eliteBorder, width: 0.8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        t['invoice']!,
                        style: pw.TextStyle(
                          fontSize: 25,
                          fontWeight: pw.FontWeight.bold,
                          color: _eliteNavy,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Text(
                      invoice.status == InvoiceStatus.none
                          ? ''
                          : invoice.status.displayName.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: _eliteGold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  invoice.invoiceNumber,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: _eliteNavy,
                  ),
                ),
                pw.SizedBox(height: 14),
                pw.Divider(color: _eliteBorder, height: 1),
                pw.SizedBox(height: 12),
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: _premiumDetailPair(
                        t['date']!,
                        _formatLocalizedDate(invoice.date, invoice.language),
                        labelColor: _textMuted,
                        valueColor: _eliteNavy,
                      ),
                    ),
                    if (_clean(invoice.paymentMethod) != null)
                      pw.Expanded(
                        child: _premiumDetailPair(
                          t['payment']!,
                          invoice.paymentMethod!,
                          labelColor: _textMuted,
                          valueColor: _eliteNavy,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _premiumClientAndMeta(
    Invoice invoice,
    Client client,
    Map<String, String> t, {
    required PdfColor accent,
    required PdfColor cardColor,
    required PdfColor borderColor,
    required String? language,
    required String? paymentMethod,
    required double taxRate,
    PdfColor? strongAccent,
  }) {
    final clientDetails = <pw.Widget>[
      pw.Text(
        client.name,
        style: pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: strongAccent ?? _textDark,
        ),
      ),
      if (_clean(client.address) != null) ...[
        pw.SizedBox(height: 3),
        pw.Text(
          client.address!,
          style: const pw.TextStyle(fontSize: 9, color: _textMuted),
        ),
      ],
      if (_clean(client.country) != null) ...[
        pw.SizedBox(height: 3),
        pw.Text(
          client.country!,
          style: const pw.TextStyle(fontSize: 9, color: _textMuted),
        ),
      ],
      if (_clean(client.taxId) != null) ...[
        pw.SizedBox(height: 3),
        pw.Text(
          client.taxId!,
          style: const pw.TextStyle(fontSize: 9, color: _textMuted),
        ),
      ],
      if (_clean(client.phone) != null) ...[
        pw.SizedBox(height: 3),
        pw.Text(
          client.phone!,
          style: const pw.TextStyle(fontSize: 9, color: _textMuted),
        ),
      ],
    ];

    final metadata = <pw.Widget>[
      _premiumDetailPair(
        t['inv_no']!,
        invoice.invoiceNumber,
        labelColor: accent,
        valueColor: strongAccent ?? _textDark,
      ),
      pw.SizedBox(height: 6),
      _premiumDetailPair(
        t['date']!,
        _formatLocalizedDate(invoice.date, language),
        labelColor: accent,
        valueColor: strongAccent ?? _textDark,
      ),
      if (invoice.status != InvoiceStatus.none) ...[
        pw.SizedBox(height: 6),
        _premiumDetailPair(
          t['status']!,
          invoice.status.displayName,
          labelColor: accent,
          valueColor: strongAccent ?? _textDark,
        ),
      ],
      if (taxRate > 0) ...[
        pw.SizedBox(height: 6),
        _premiumDetailPair(
          t['tax_rate']!,
          '${taxRate.toStringAsFixed(1)}%',
          labelColor: accent,
          valueColor: strongAccent ?? _textDark,
        ),
      ],
      if (paymentMethod != null) ...[
        pw.SizedBox(height: 6),
        _premiumDetailPair(
          t['payment']!,
          paymentMethod,
          labelColor: accent,
          valueColor: strongAccent ?? _textDark,
        ),
      ],
    ];

    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: cardColor,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        border: pw.Border.all(color: borderColor, width: 0.8),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  t['bill_to']!,
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: accent,
                    letterSpacing: 1,
                  ),
                ),
                pw.SizedBox(height: 6),
                ...clientDetails,
              ],
            ),
          ),
          pw.SizedBox(width: 18),
          pw.SizedBox(
            width: 172,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  t['invoice_details']!,
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: accent,
                    letterSpacing: 1,
                  ),
                ),
                pw.SizedBox(height: 6),
                ...metadata,
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _premiumItemsTable(
    List<InvoiceItem> items,
    String currencySymbol,
    String currencyCode,
    String? language,
    double taxRate, {
    required PdfColor headerColor,
    required PdfColor alternateColor,
    required PdfColor borderColor,
    required Map<String, String> t,
  }) {
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(3.3),
        1: pw.FlexColumnWidth(0.75),
        2: pw.FlexColumnWidth(1.35),
        3: pw.FlexColumnWidth(0.95),
        4: pw.FlexColumnWidth(1.55),
      },
      border: pw.TableBorder.all(color: borderColor, width: 0.5),
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: headerColor),
          children: [
            _tableHeader(t['desc']!),
            _tableHeader(t['qty']!, align: pw.TextAlign.center),
            _tableHeader(t['price']!, align: pw.TextAlign.right),
            _tableHeader(t['tax']!, align: pw.TextAlign.right),
            _tableHeader(t['total']!, align: pw.TextAlign.right),
          ],
        ),
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final rowSubtotal = item.unitPrice * item.quantity;
          final rowTax = rowSubtotal * taxRate / 100;
          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: index.isEven ? _white : alternateColor,
            ),
            children: [
              _tableCell(item.description),
              _tableCell(item.quantity.toString(), align: pw.TextAlign.center),
              _tableCell(
                _formatMoney(
                  item.unitPrice,
                  currencyCode,
                  currencySymbol,
                  language,
                ),
                align: pw.TextAlign.right,
              ),
              _tableCell(
                taxRate > 0 ? '${taxRate.toStringAsFixed(1)}%' : '—',
                align: pw.TextAlign.right,
              ),
              _tableCell(
                _formatMoney(
                  rowSubtotal + rowTax,
                  currencyCode,
                  currencySymbol,
                  language,
                ),
                align: pw.TextAlign.right,
                bold: true,
              ),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _premiumSupportingInfo({
    required String? paymentDetails,
    required String? paymentMethod,
    required String? notes,
    required Map<String, String> t,
    required PdfColor accent,
    required PdfColor cardColor,
    required PdfColor borderColor,
  }) {
    final children = <pw.Widget>[];
    if (paymentDetails != null || paymentMethod != null) {
      children.add(_sectionLabel(t['payment_details']!, color: accent));
      if (paymentMethod != null) {
        children.add(pw.SizedBox(height: 5));
        children.add(
          pw.Text(
            paymentMethod,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _textDark,
            ),
          ),
        );
      }
      if (paymentDetails != null) {
        children.add(pw.SizedBox(height: 4));
        children.add(
          pw.Text(
            paymentDetails,
            style: const pw.TextStyle(
              fontSize: 9,
              color: _textDark,
              height: 1.3,
            ),
          ),
        );
      }
    }
    if (notes != null) {
      if (children.isNotEmpty) children.add(pw.SizedBox(height: 12));
      children.add(_sectionLabel(t['notes']!, color: accent));
      children.add(pw.SizedBox(height: 4));
      children.add(
        pw.Text(
          notes,
          style: const pw.TextStyle(fontSize: 9, color: _textDark, height: 1.3),
        ),
      );
    }
    if (children.isEmpty) return pw.SizedBox();

    return pw.Container(
      padding: const pw.EdgeInsets.all(13),
      decoration: pw.BoxDecoration(
        color: cardColor,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: borderColor, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  static pw.Widget _premiumTotals({
    required double subtotal,
    required double taxRate,
    required double taxAmount,
    required double grandTotal,
    required String currencySymbol,
    required String currencyCode,
    required String? language,
    required Map<String, String> t,
    required PdfColor accent,
    required PdfColor cardColor,
    required PdfColor valueColor,
    required PdfColor borderColor,
    required PdfColor totalLabelColor,
  }) {
    String money(double value) =>
        _formatMoney(value, currencyCode, currencySymbol, language);

    return pw.Container(
      padding: const pw.EdgeInsets.all(13),
      decoration: pw.BoxDecoration(
        color: cardColor,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(9)),
        border: pw.Border.all(color: borderColor, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _premiumAmountRow(t['subtotal']!, money(subtotal), valueColor),
          if (taxRate > 0) ...[
            pw.SizedBox(height: 5),
            _premiumAmountRow(
              '${t['tax']!} (${taxRate.toStringAsFixed(1)}%)',
              money(taxAmount),
              valueColor,
            ),
          ],
          pw.SizedBox(height: 10),
          pw.Divider(color: borderColor, height: 1),
          pw.SizedBox(height: 10),
          pw.Text(
            t['grand_total']!,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: totalLabelColor,
              letterSpacing: 0.8,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            money(grandTotal),
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
              color: accent == _eliteGold ? _white : totalLabelColor,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _premiumAmountRow(
    String label,
    String value,
    PdfColor color,
  ) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Text(label, style: pw.TextStyle(fontSize: 8.5, color: color)),
      ),
      pw.SizedBox(width: 8),
      pw.Text(
        value,
        textAlign: pw.TextAlign.right,
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
          color: color,
        ),
      ),
    ],
  );

  static pw.Widget _premiumIssuedBy(
    BusinessProfile profile,
    bool isPro, {
    required PdfColor accent,
    required Map<String, String> t,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 9),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: accent, width: 0.7)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Text(
            isPro
                ? '${t['issued_by']!} ${profile.name}'
                : 'Generated by Centsio AI: Invoice Maker',
            style: pw.TextStyle(fontSize: 8, color: _textMuted),
          ),
        ],
      ),
    );
  }

  static pw.Widget _premiumLogo(
    pw.MemoryImage? logoImage,
    String businessName, {
    required PdfColor fallbackColor,
    required PdfColor fallbackTextColor,
    bool circleFallback = false,
  }) {
    final initial = businessName.trim().isEmpty
        ? 'F'
        : businessName.trim()[0].toUpperCase();
    return pw.Container(
      width: 52,
      height: 52,
      decoration: pw.BoxDecoration(
        color: logoImage == null ? fallbackColor : _white,
        shape: circleFallback ? pw.BoxShape.circle : pw.BoxShape.rectangle,
        borderRadius: circleFallback
            ? null
            : const pw.BorderRadius.all(pw.Radius.circular(9)),
        image: logoImage == null
            ? null
            : pw.DecorationImage(image: logoImage, fit: pw.BoxFit.contain),
      ),
      child: logoImage == null
          ? pw.Center(
              child: pw.Text(
                initial,
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: fallbackTextColor,
                ),
              ),
            )
          : null,
    );
  }

  static pw.Widget _premiumDetailPair(
    String label,
    String value, {
    required PdfColor labelColor,
    required PdfColor valueColor,
  }) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(label, style: pw.TextStyle(fontSize: 7.5, color: labelColor)),
      pw.SizedBox(height: 2),
      pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: valueColor,
        ),
      ),
    ],
  );

  static pw.Widget _premiumHeaderMeta(
    String label,
    String value, {
    required PdfColor color,
  }) => pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Text('$label: ', style: pw.TextStyle(fontSize: 7.5, color: color)),
      pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: 7.5,
          fontWeight: pw.FontWeight.bold,
          color: color,
        ),
      ),
    ],
  );

  static pw.Widget _premiumRunningHeader(
    pw.Context context,
    BusinessProfile profile,
    Invoice invoice,
    Map<String, String> t,
    String template,
  ) {
    if (context.pageNumber == 1) return pw.SizedBox();
    final accent = template == 'Elite' ? _eliteGold : _modernTeal;
    final background = template == 'Elite' ? _eliteNavy : _modernTeal;
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: accent, width: 1)),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            profile.name,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: pw.FontWeight.bold,
              color: background,
            ),
          ),
          pw.Spacer(),
          pw.Text(
            '${t['invoice']} · ${invoice.invoiceNumber}',
            style: pw.TextStyle(fontSize: 8, color: _textMuted),
          ),
        ],
      ),
    );
  }

  static pw.Widget _premiumFooter(pw.Context context, Map<String, String> t) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _borderGrey, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            t['issued_by']!,
            style: const pw.TextStyle(fontSize: 7.5, color: _textMuted),
          ),
          pw.Text(
            '${t['page']!} ${context.pageNumber}',
            style: const pw.TextStyle(fontSize: 7.5, color: _textMuted),
          ),
        ],
      ),
    );
  }

  static double _subtotal(List<InvoiceItem> items) => items.fold<double>(
    0,
    (sum, item) => sum + item.unitPrice * item.quantity,
  );

  static String? _clean(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }

  static String _formatMoney(
    double amount,
    String currencyCode,
    String currencySymbol,
    String? language,
  ) {
    final code = currencyCode.trim().isEmpty
        ? 'USD'
        : currencyCode.trim().toUpperCase();
    final locale = switch (code) {
      'EUR' => 'de_DE',
      'GBP' => 'en_GB',
      'CHF' => 'de_CH',
      'MAD' => 'fr_MA',
      'CAD' => 'en_CA',
      'AUD' => 'en_AU',
      'INR' => 'en_IN',
      'JPY' => 'ja_JP',
      'BRL' => 'pt_BR',
      'SEK' => 'sv_SE',
      'NOK' => 'nb_NO',
      'DKK' => 'da_DK',
      'PLN' => 'pl_PL',
      _ =>
        language == 'Français'
            ? 'fr_FR'
            : (language == 'Español' ? 'es_ES' : 'en_US'),
    };
    final digits = code == 'JPY' ? 0 : 2;
    try {
      return NumberFormat.currency(
        locale: locale,
        name: code,
        symbol: currencySymbol,
        decimalDigits: digits,
      ).format(amount);
    } catch (_) {
      return '$currencySymbol${amount.toStringAsFixed(digits)}';
    }
  }

  static String _asciiSafeCurrencySymbol(String symbol, String code) {
    final isAscii = symbol.codeUnits.every((unit) => unit < 128);
    return isAscii ? symbol : code;
  }

  static String _formatLocalizedDate(DateTime date, String? language) {
    final locale = language == 'Français'
        ? 'fr_FR'
        : (language == 'Español' ? 'es_ES' : 'en_US');
    try {
      return DateFormat.yMMMd(locale).format(date);
    } catch (_) {
      return _formatDate(date);
    }
  }

  // ── Shared Header ─────────────────────────────────────────────────────────

  static pw.Widget _header(
    Invoice invoice,
    BusinessProfile profile,
    pw.MemoryImage? logoImage,
    Map<String, String> t,
  ) {
    final firstLetter = profile.name.trim().isNotEmpty
        ? profile.name.trim()[0].toUpperCase()
        : 'F';

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logoImage != null)
          pw.Container(
            width: 64,
            height: 64,
            decoration: pw.BoxDecoration(
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              image: pw.DecorationImage(
                image: logoImage,
                fit: pw.BoxFit.contain,
              ),
            ),
          )
        else
          pw.Container(
            width: 64,
            height: 64,
            decoration: const pw.BoxDecoration(
              color: _accentEmerald,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
            ),
            child: pw.Center(
              child: pw.Text(
                firstLetter,
                style: pw.TextStyle(
                  fontSize: 26,
                  fontWeight: pw.FontWeight.bold,
                  color: _white,
                ),
              ),
            ),
          ),
        pw.SizedBox(width: 16),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              profile.name,
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: _textDark,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              profile.tagline,
              style: pw.TextStyle(fontSize: 10, color: _textMuted),
            ),
            if (profile.address != null) ...[
              pw.SizedBox(height: 2),
              pw.Text(
                profile.address!,
                style: pw.TextStyle(fontSize: 9, color: _textMuted),
              ),
            ],
            if (profile.taxId != null && profile.taxId!.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text(
                profile.taxId!.contains(':')
                    ? profile.taxId!
                    : 'Tax ID: ${profile.taxId!}',
                style: pw.TextStyle(fontSize: 9, color: _textMuted),
              ),
            ],
          ],
        ),
        pw.Spacer(),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              t['invoice']!,
              style: pw.TextStyle(
                fontSize: 30,
                fontWeight: pw.FontWeight.bold,
                color: _textDark,
                letterSpacing: 2,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              decoration: const pw.BoxDecoration(
                color: _accentEmerald,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Text(
                invoice.invoiceNumber,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: _white,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            _metaRow(t['date']!, _formatDate(invoice.date)),
          ],
        ),
      ],
    );
  }

  // ── Billing section ────────────────────────────────────────────────────────

  static pw.Widget _billingRow(
    Invoice invoice,
    Client client,
    BusinessProfile profile,
    Map<String, String> t,
  ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _bgLight,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        border: pw.Border.all(color: _borderGrey, width: 0.5),
      ),
      padding: const pw.EdgeInsets.all(18),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _sectionLabel(t['bill_to']!),
                pw.SizedBox(height: 6),
                pw.Text(
                  client.name,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: _textDark,
                  ),
                ),
                if (client.address != null) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    client.address!,
                    style: pw.TextStyle(fontSize: 9.5, color: _textMuted),
                  ),
                ],
                if (client.country != null && client.country!.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Country: ${client.country!}',
                    style: pw.TextStyle(fontSize: 9.5, color: _textMuted),
                  ),
                ],
                if (client.taxId != null && client.taxId!.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    client.taxId!.contains(':')
                        ? client.taxId!
                        : '${_getTaxLabel(client.country)}: ${client.taxId!}',
                    style: pw.TextStyle(fontSize: 9.5, color: _textMuted),
                  ),
                ],
                if (client.phone != null) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    client.phone!,
                    style: pw.TextStyle(fontSize: 9.5, color: _textMuted),
                  ),
                ],
              ],
            ),
          ),
          pw.Container(width: 0.5, height: 75, color: _borderGrey),
          pw.SizedBox(width: 20),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _sectionLabel(t['invoice_details']!),
              pw.SizedBox(height: 6),
              _detailRow(t['inv_no']!, invoice.invoiceNumber),
              pw.SizedBox(height: 3),
              _detailRow(t['date']!, _formatDate(invoice.date)),
              pw.SizedBox(height: 3),
              _detailRow(
                t['tax_rate']!,
                '${invoice.taxRate.toStringAsFixed(1)}%',
              ),
              pw.SizedBox(height: 3),
              _detailRow(
                t['payment'] ?? 'Payment',
                invoice.paymentMethod ?? 'Bank Transfer',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Items table ───────────────────────────────────────────────────────────

  static pw.Widget _itemsTable(
    List<InvoiceItem> items,
    String currencySymbol,
    Map<String, String> t,
  ) {
    const colWidths = [
      pw.FlexColumnWidth(3.0),
      pw.FlexColumnWidth(0.8),
      pw.FlexColumnWidth(1.8),
      pw.FlexColumnWidth(1.8),
    ];

    return pw.Table(
      columnWidths: {
        0: colWidths[0],
        1: colWidths[1],
        2: colWidths[2],
        3: colWidths[3],
      },
      border: pw.TableBorder.all(color: _borderGrey, width: 0.5),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _headerFill),
          children: [
            _tableHeader(t['desc']!),
            _tableHeader(t['qty']!, align: pw.TextAlign.center),
            _tableHeader(t['price']!, align: pw.TextAlign.right),
            _tableHeader(t['total']!, align: pw.TextAlign.right),
          ],
        ),
        ...items.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          final rowTotal = item.unitPrice * item.quantity;
          final isEven = idx.isEven;
          return pw.TableRow(
            decoration: pw.BoxDecoration(color: isEven ? _white : _bgLight),
            children: [
              _tableCell(item.description),
              _tableCell(item.quantity.toString(), align: pw.TextAlign.center),
              _tableCell(
                '$currencySymbol${item.unitPrice.toStringAsFixed(2)}',
                align: pw.TextAlign.right,
              ),
              _tableCell(
                '$currencySymbol${rowTotal.toStringAsFixed(2)}',
                align: pw.TextAlign.right,
                bold: true,
              ),
            ],
          );
        }),
      ],
    );
  }

  // ── Totals section ─────────────────────────────────────────────────────────

  static pw.Widget _totalsSection(
    Invoice invoice,
    List<InvoiceItem> items,
    String currencySymbol,
    Map<String, String> t,
  ) {
    final subtotal = items.fold<double>(
      0,
      (s, i) => s + i.unitPrice * i.quantity,
    );
    final taxAmount = subtotal * (invoice.taxRate / 100);
    final grandTotal = subtotal + taxAmount;

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Spacer(),
        pw.SizedBox(
          width: 210,
          child: pw.Column(
            children: [
              _totalRow(
                t['subtotal']!,
                '$currencySymbol${subtotal.toStringAsFixed(2)}',
              ),
              pw.SizedBox(height: 4),
              if (invoice.taxRate > 0) ...[
                _totalRow(
                  '${t['tax']!} (${invoice.taxRate.toStringAsFixed(1)}%)',
                  '$currencySymbol${taxAmount.toStringAsFixed(2)}',
                ),
                pw.SizedBox(height: 4),
              ],
              pw.Divider(color: _borderGrey, height: 14),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: const pw.BoxDecoration(
                  color: _headerFill,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      t['grand_total']!,
                      style: pw.TextStyle(
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                        color: _white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    pw.Text(
                      '$currencySymbol${grandTotal.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: _accentEmerald,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Bank details section (RIB / IBAN) ──────────────────────────────────────

  static pw.Widget _bankDetailsSection(
    BusinessProfile profile,
    Map<String, String> t,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _bgLight,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: _borderGrey, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionLabel(t['payment_details']!),
          pw.SizedBox(height: 6),
          pw.Text(
            profile.bankDetails!,
            style: pw.TextStyle(fontSize: 9.5, color: _textDark, height: 1.35),
          ),
        ],
      ),
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────────

  static pw.Widget _footer(
    Invoice invoice,
    BusinessProfile profile,
    bool isPro,
    Map<String, String> t,
  ) {
    final noteText = (invoice.notes != null && invoice.notes!.trim().isNotEmpty)
        ? invoice.notes!.trim()
        : t['thanks']!;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Divider(color: _borderGrey),
        pw.SizedBox(height: 6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              noteText,
              style: pw.TextStyle(
                fontSize: 9.5,
                fontStyle: pw.FontStyle.italic,
                color: _textMuted,
              ),
            ),
            pw.Text(
              isPro
                  ? '${t['issued_by']!} ${profile.name}'
                : 'Generated by Centsio AI: Invoice Maker',
              style: pw.TextStyle(
                fontSize: isPro ? 8 : 8.5,
                color: isPro ? _textMuted : _accentEmerald,
                fontWeight: isPro ? pw.FontWeight.normal : pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static pw.Widget _sectionLabel(String label, {PdfColor? color}) => pw.Text(
    label,
    style: pw.TextStyle(
      fontSize: 8.5,
      fontWeight: pw.FontWeight.bold,
      color: color ?? _textMuted,
      letterSpacing: 0.8,
    ),
  );

  static pw.Widget _detailRow(String label, String value) => pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Text('$label: ', style: pw.TextStyle(fontSize: 9, color: _textMuted)),
      pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: _textDark,
        ),
      ),
    ],
  );

  static pw.Widget _metaRow(
    String label,
    String value, {
    PdfColor? valueColor,
  }) => pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Text(
        '$label: ',
        style: pw.TextStyle(fontSize: 9.5, color: _textMuted),
      ),
      pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: 9.5,
          fontWeight: pw.FontWeight.bold,
          color: valueColor ?? _textDark,
        ),
      ),
    ],
  );

  static pw.Widget _tableHeader(String label, {pw.TextAlign? align}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: pw.Text(
          label,
          textAlign: align ?? pw.TextAlign.left,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: _white,
            letterSpacing: 0.5,
          ),
        ),
      );

  static pw.Widget _tableCell(
    String text, {
    pw.TextAlign? align,
    bool bold = false,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    child: pw.Text(
      text,
      textAlign: align ?? pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: 9.5,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: _textDark,
      ),
    ),
  );

  static pw.Widget _totalRow(String label, String value) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(label, style: pw.TextStyle(fontSize: 9.5, color: _textMuted)),
      pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: 9.5,
          fontWeight: pw.FontWeight.bold,
          color: _textDark,
        ),
      ),
    ],
  );

  static String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}
