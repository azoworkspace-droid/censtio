import 'package:flutter_test/flutter_test.dart';
import 'package:freelancer/services/gemini_service.dart';

void main() {
  group('GeminiService invoice parsing', () {
    test('parses valid JSON and markdown code fences', () {
      final result = GeminiService.parseInvoiceResponse('''
```json
{"clientName":"Acme","items":[{"description":"Design","unitPrice":125.5,"quantity":2}],"notes":"Thank you"}
```
''');

      expect(result, isNotNull);
      expect(result!.clientName, 'Acme');
      expect(result.items.single.description, 'Design');
      expect(result.items.single.unitPrice, 125.5);
      expect(result.items.single.quantity, 2);
      expect(result.notes, 'Thank you');
    });

    test('rejects invoices without valid line items', () {
      final result = GeminiService.parseInvoiceResponse(
        '{"clientName":"Acme","items":[{"description":"","unitPrice":0,"quantity":1}]}',
      );

      expect(result, isNull);
    });

    test('accepts numeric strings and surrounding explanatory text', () {
      final result = GeminiService.parseInvoiceResponse('''
Here is the extracted data:
{"items":[{"description":"Consulting","unitPrice":"1,250.50","quantity":"2"}]}
''');

      expect(result, isNotNull);
      expect(result!.items.single.unitPrice, 1250.5);
      expect(result.items.single.quantity, 2);
    });

    test('ignores malformed line items but keeps valid ones', () {
      final result = GeminiService.parseInvoiceResponse('''
{"items":[
  {"description":"bad","unitPrice":-2,"quantity":1},
  {"description":"Hosting","unitPrice":20,"quantity":1.0}
]}
''');

      expect(result, isNotNull);
      expect(result!.items.length, 1);
      expect(result.items.single.description, 'Hosting');
    });

    test('parses strict draft OCR price and qty fields', () {
      final result = GeminiService.parseDraftInvoiceResponse('''
{"clientName":"Atlas","items":[{"description":"Website","price":1500.5,"qty":2}]}
''');

      expect(result, isNotNull);
      expect(result!.clientName, 'Atlas');
      expect(result.items.single.unitPrice, 1500.5);
      expect(result.items.single.quantity, 2);
    });
  });

  group('GeminiService expense parsing', () {
    test('normalizes supported category aliases', () {
      final result = GeminiService.parseExpenseResponse(
        '{"amount":42.25,"category":"Office Supplies","note":"Paper"}',
      );

      expect(result, isNotNull);
      expect(result!.amount, 42.25);
      expect(result.category, 'office');
      expect(result.note, 'Paper');
    });

    test(
      'falls back to Other for unknown categories and rejects unsafe amounts',
      () {
        expect(
          GeminiService.parseExpenseResponse(
            '{"amount":-1,"category":"Office","note":"x"}',
          ),
          isNull,
        );
        final unknownCategory = GeminiService.parseExpenseResponse(
          '{"amount":10,"category":"Gambling","note":"x"}',
        );
        expect(unknownCategory, isNotNull);
        expect(unknownCategory!.category, 'other');
      },
    );

    test('parses comma decimal currency values', () {
      final result = GeminiService.parseExpenseResponse(
        '{"amount":"237,60 MAD","category":"Other","note":"Receipt"}',
      );

      expect(result, isNotNull);
      expect(result!.amount, 237.60);
    });
  });
}
