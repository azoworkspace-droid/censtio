import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:freelancer/models/invoice.dart';
import 'package:freelancer/services/app_database.dart';
import 'package:freelancer/services/pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'business_name':
          'Northstar Creative Studio and Professional Consulting Group',
      'business_tagline': 'Brand systems, strategy, and digital products',
      'business_address':
          '100 Long Market Street, Suite 204, New York, NY 10001, United States',
      'business_tax_id': 'EIN: 12-3456789',
      'business_bank_details':
          'Bank transfer · Account holder: Northstar Creative Studio · Routing and account details available on request',
      'show_payment_details_on_invoices': true,
      'currency_code': 'EUR',
      'currency_symbol': '€',
    });
  });

  final invoice = Invoice(
    id: 1,
    invoiceNumber: 'INV-2026-NORTHSTAR-000001',
    date: DateTime(2026, 8, 8),
    clientId: 1,
    totalAmount: 0,
    taxRate: 21,
    status: InvoiceStatus.pending,
    language: 'English',
    template: 'Modern',
    documentType: 'invoice',
    paymentMethod: 'Bank transfer',
    notes:
        'Thank you for working with us. Payment is due according to the agreed project terms.',
  );

  final client = Client(
    id: 1,
    name: 'International Client Partnership and Advisory Services',
    address:
        '42 Long Avenue, Floor 7, Financial District, London, United Kingdom',
    taxId: 'GB123456789',
    phone: '+44 20 7946 0958',
    country: 'United Kingdom',
    language: 'English',
  );

  final items = List<InvoiceItem>.generate(
    34,
    (index) => InvoiceItem(
      id: index + 1,
      description:
          'Professional consulting, delivery, and project coordination workstream ${index + 1}',
      unitPrice: 125.75 + index,
      quantity: (index % 3) + 1,
    ),
  );

  test('Modern renders localized long-content invoices', () async {
    final bytes = await PdfService.generateInvoicePdf(
      invoice: invoice,
      client: client,
      items: items,
      templateType: 'Modern',
    );

    expect(bytes, isNotEmpty);
  });

  test('Elite renders long-content invoices across multiple pages', () async {
    final bytes = await PdfService.generateInvoicePdf(
      invoice: invoice.copyWith(template: const Value('Elite')),
      client: client,
      items: items,
      templateType: 'Elite',
      pageFormat: PdfPageFormat.letter,
    );

    expect(bytes, isNotEmpty);
  });
}
