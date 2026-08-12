import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

/// A user-safe error raised when Gemini cannot produce usable app data.
class AiServiceException implements Exception {
  const AiServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiInvoiceItem {
  const AiInvoiceItem({
    required this.description,
    required this.unitPrice,
    required this.quantity,
  });

  final String description;
  final double unitPrice;
  final int quantity;

  Map<String, dynamic> toMap() => {
    'description': description,
    'unitPrice': unitPrice,
    'quantity': quantity,
  };
}

class AiInvoiceData {
  const AiInvoiceData({this.clientName, required this.items, this.notes});

  final String? clientName;
  final List<AiInvoiceItem> items;
  final String? notes;

  Map<String, dynamic> toMap() => {
    if (clientName != null) 'clientName': clientName,
    'items': items.map((item) => item.toMap()).toList(),
    if (notes != null) 'notes': notes,
  };
}

class AiExpenseData {
  const AiExpenseData({
    required this.amount,
    required this.category,
    required this.note,
  });

  final double amount;

  /// One of the app's category names: software, travel, office, marketing,
  /// meals, or other.
  final String category;
  final String note;

  Map<String, dynamic> toMap() => {
    'amount': amount,
    'category': category,
    'note': note,
  };
}

class GeminiService {
  GeminiService._();

  static const _modelName = 'gemini-3.5-flash';
  static const _fallbackModelName = 'gemini-2.5-flash';
  static const _maxImageBytes = 15 * 1024 * 1024;
  static const _maxTranscriptLength = 4000;
  static const _maxMoney = 100000000.0;

  static GenerativeModel _model([
    String modelName = _modelName,
    String? systemInstruction,
  ]) {
    final apiKey = dotenv.env['GEMINI_API_KEY']?.trim();
    if (apiKey == null || apiKey.isEmpty || apiKey == 'your_api_key_here') {
      throw const AiServiceException(
        'Gemini is not configured. Add GEMINI_API_KEY to the .env file.',
      );
    }

    return GenerativeModel(
      model: modelName,
      apiKey: apiKey,
      generationConfig: GenerationConfig(responseMimeType: 'application/json'),
      systemInstruction: systemInstruction == null
          ? null
          : Content.system(systemInstruction),
    );
  }

  static void _validateImage(Uint8List imageBytes) {
    if (imageBytes.isEmpty) {
      throw const AiServiceException('The selected image is empty.');
    }
    if (imageBytes.length > _maxImageBytes) {
      throw const AiServiceException(
        'The image is too large. Please choose an image under 15 MB.',
      );
    }
  }

  static String _validateTranscript(String transcript) {
    final value = transcript.trim();
    if (value.isEmpty) {
      throw const AiServiceException(
        'No speech was detected. Please try again.',
      );
    }
    if (value.length > _maxTranscriptLength) {
      return value.substring(0, _maxTranscriptLength);
    }
    return value;
  }

  /// Analyzes a purchase receipt: money going out of the business.
  static Future<AiExpenseData?> analyzeReceiptForExpense(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
    String currencySymbol = '\$',
  }) async {
    _validateImage(imageBytes);
    final systemPrompt =
        '''
You are an expert accountant. Analyze this receipt image. The user is scanning
a purchase receipt for an expense: money going OUT of the business.
Extract the final paid total, guess the business category, and extract the
merchant name or a short note. Return ONLY a valid JSON object.
The category must be exactly one of: Software, Travel, Office, Marketing,
Meals, Other. Do not invent an amount that is not readable.
Expected JSON schema exactly:
{"amount": double, "category": String, "note": String}
The app currency is ${jsonEncode(currencySymbol)}. Return a numeric amount
without a currency symbol and do not convert it.
''';
    final response = await _generateImage(
      'Analyze the supplied receipt image.',
      imageBytes,
      mimeType,
      systemInstruction: systemPrompt,
    );
    final data = parseExpenseResponse(response);
    if (data == null) {
      throw const AiServiceException(
        'I could not find a reliable paid total on this receipt. Try a clearer, well-lit photo.',
      );
    }
    return data;
  }

  /// Backward-compatible alias for callers using the previous API name.
  @Deprecated('Use analyzeReceiptForExpense instead.')
  static Future<AiExpenseData?> analyzeReceipt(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
    String currencySymbol = '\$',
  }) => analyzeReceiptForExpense(
    imageBytes,
    mimeType: mimeType,
    currencySymbol: currencySymbol,
  );

  static Future<AiInvoiceData?> analyzeVoiceInvoice(
    String transcript, {
    String currencySymbol = '\$',
  }) async {
    final value = _validateTranscript(transcript);
    final prompt =
        '''
Convert this spoken invoice or quote description to JSON only.
Required schema: {"clientName": string|null, "items": [{"description": string, "unitPrice": number, "quantity": integer}], "notes": string|null}.
Never invent a price or quantity. Use quantity 1 only when the wording clearly
describes one item. Return an empty items array if no billable item is present.
The app's selected currency is ${jsonEncode(currencySymbol)}. Return numeric
prices without currency symbols and do not convert them.
Transcript: ${jsonEncode(value)}
''';

    final response = await _generateText(prompt);
    final data = parseInvoiceResponse(response);
    if (data == null) {
      throw const AiServiceException(
        'I could not find a reliable billable item. Please describe the item and price again.',
      );
    }
    return data;
  }

  /// Analyzes a draft/handwritten document: money coming into the business.
  static Future<AiInvoiceData?> analyzeDraftForInvoice(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
    String currencySymbol = '\$',
  }) async {
    _validateImage(imageBytes);
    final systemPrompt =
        '''
You are an expert billing assistant. Analyze this draft document or handwritten
note. The user is generating a formal invoice for a client: money coming IN to
the business.
Extract the client's name if visible and every reliable billable line item.
Return ONLY a valid JSON object. Do not invent a price or quantity. Return an
empty items array if no reliable line item can be found.
Expected JSON schema exactly:
{"clientName": String, "items": [{"description": String, "price": double, "qty": int}]}
The app currency is ${jsonEncode(currencySymbol)}. Return numeric prices
without currency symbols and do not convert them.
''';
    final response = await _generateImage(
      'Analyze the supplied draft or handwritten document.',
      imageBytes,
      mimeType,
      systemInstruction: systemPrompt,
    );
    final data = parseDraftInvoiceResponse(response);
    if (data == null) {
      throw const AiServiceException(
        'I could not find reliable billable items in this draft. Try a clearer photo.',
      );
    }
    return data;
  }

  /// Backward-compatible alias for callers using the previous API name.
  @Deprecated('Use analyzeDraftForInvoice instead.')
  static Future<AiInvoiceData?> analyzeInvoiceImage(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
    String currencySymbol = '\$',
  }) => analyzeDraftForInvoice(
    imageBytes,
    mimeType: mimeType,
    currencySymbol: currencySymbol,
  );

  static Future<AiExpenseData?> analyzeVoiceExpense(
    String transcript, {
    String currencySymbol = '\$',
  }) async {
    final value = _validateTranscript(transcript);
    final prompt =
        '''
Convert this spoken expense description to JSON only.
Required schema: {"amount": number, "category": "Software|Travel|Office|Marketing|Meals|Other", "note": string}.
Do not guess an amount. Return null for the response if no reliable amount is
present. Transcript: ${jsonEncode(value)}
The app's selected currency is ${jsonEncode(currencySymbol)}. Return the
numeric amount without a currency symbol and do not convert it.
''';

    final response = await _generateText(prompt);
    final data = parseExpenseResponse(response);
    if (data == null) {
      throw const AiServiceException(
        'I could not find a reliable amount. Say the amount and what it was for, then try again.',
      );
    }
    return data;
  }

  static Future<String> _generateText(String prompt) async {
    Object? lastError;
    for (final modelName in [_modelName, _fallbackModelName]) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final response = await _model(modelName)
              .generateContent([Content.text(prompt)])
              .timeout(const Duration(seconds: 45));
          final text = response.text?.trim();
          if (text == null || text.isEmpty) {
            throw const AiServiceException(
              'Gemini returned an empty response.',
            );
          }
          return text;
        } catch (error) {
          lastError = error;
          if (!_isTransient(error) || attempt == 1) break;
          await Future<void>.delayed(const Duration(milliseconds: 900));
        }
      }
    }
    debugPrint('Gemini text request failed: $lastError');
    if (lastError is AiServiceException) throw lastError;
    throw AiServiceException(_friendlyError(lastError ?? 'unknown error'));
  }

  static Future<String> _generateImage(
    String prompt,
    Uint8List imageBytes,
    String mimeType, {
    String? systemInstruction,
  }) async {
    Object? lastError;
    for (final modelName in [_modelName, _fallbackModelName]) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final response = await _model(modelName, systemInstruction)
              .generateContent([
                Content.multi([
                  TextPart(prompt),
                  DataPart(mimeType, imageBytes),
                ]),
              ])
              .timeout(const Duration(seconds: 45));
          final text = response.text?.trim();
          if (text == null || text.isEmpty) {
            throw const AiServiceException(
              'Gemini returned an empty response.',
            );
          }
          return text;
        } catch (error) {
          lastError = error;
          if (!_isTransient(error) || attempt == 1) break;
          await Future<void>.delayed(const Duration(milliseconds: 900));
        }
      }
    }
    debugPrint('Gemini image request failed: $lastError');
    if (lastError is AiServiceException) throw lastError;
    throw AiServiceException(
      _friendlyError(lastError ?? 'unknown error', image: true),
    );
  }

  static bool _isTransient(Object error) {
    final detail = error.toString().toLowerCase();
    return detail.contains('503') ||
        detail.contains('502') ||
        detail.contains('504') ||
        detail.contains('unavailable') ||
        detail.contains('temporarily') ||
        detail.contains('timeout');
  }

  static String _friendlyError(Object error, {bool image = false}) {
    final detail = error.toString().toLowerCase();
    if (detail.contains('401') ||
        detail.contains('403') ||
        detail.contains('api key') ||
        detail.contains('unauthorized')) {
      return 'Gemini API key is invalid or not enabled for this project.';
    }
    if (detail.contains('429') ||
        detail.contains('quota') ||
        detail.contains('rate')) {
      return 'Gemini usage limit reached. Please try again later.';
    }
    if (detail.contains('timeout')) {
      return 'Gemini took too long to respond. Check your connection and try again.';
    }
    if (detail.contains('503') || detail.contains('unavailable')) {
      return 'Gemini is temporarily busy. Please try again in a few seconds.';
    }
    return image
        ? 'Gemini could not read the image. Try a clearer, well-lit photo.'
        : 'Gemini could not process the request. Check your connection and try again.';
  }

  /// Public parsing helpers make the most important AI behavior unit-testable
  /// without calling the network.
  /// Parses the strict `{price, qty}` schema returned by draft OCR.
  static AiInvoiceData? parseDraftInvoiceResponse(String raw) {
    return parseInvoiceResponse(raw);
  }

  static AiInvoiceData? parseInvoiceResponse(String raw) {
    final decoded = _decodeObject(raw);
    if (decoded == null) return null;

    final rawItems = decoded['items'];
    if (rawItems is! List) return null;

    final items = <AiInvoiceItem>[];
    for (final rawItem in rawItems.take(50)) {
      if (rawItem is! Map) {
        continue;
      }
      final description = _string(rawItem['description'], maxLength: 500);
      // Draft OCR uses the context-specific `price`/`qty` schema. The legacy
      // names remain accepted for voice and existing saved test fixtures.
      final unitPrice = _positiveNumber(
        rawItem['price'] ?? rawItem['unitPrice'],
      );
      final quantity = _positiveInt(rawItem['qty'] ?? rawItem['quantity']);
      if (description == null || unitPrice == null || quantity == null) {
        continue;
      }
      items.add(
        AiInvoiceItem(
          description: description,
          unitPrice: unitPrice,
          quantity: quantity,
        ),
      );
    }
    if (items.isEmpty) return null;

    return AiInvoiceData(
      clientName: _string(decoded['clientName'], maxLength: 200),
      items: items,
      notes: _string(decoded['notes'], maxLength: 1000),
    );
  }

  static AiExpenseData? parseExpenseResponse(String raw) {
    final decoded = _decodeObject(raw);
    if (decoded == null) return null;
    final amount = _positiveNumber(decoded['amount']);
    final category = _category(decoded['category']);
    final note = _string(decoded['note'], maxLength: 500) ?? '';
    if (amount == null || category == null) return null;
    return AiExpenseData(amount: amount, category: category, note: note);
  }

  static Map<String, dynamic>? _decodeObject(String raw) {
    var value = raw.trim();
    if (value.startsWith('```')) {
      value = value.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      value = value.replaceFirst(RegExp(r'\s*```$'), '');
    }
    try {
      Object? decoded;
      try {
        decoded = jsonDecode(value);
      } on FormatException {
        // Be tolerant if a model adds a short sentence before/after JSON.
        final start = value.indexOf('{');
        final end = value.lastIndexOf('}');
        if (start < 0 || end <= start) return null;
        decoded = jsonDecode(value.substring(start, end + 1));
      }
      return decoded is Map<String, dynamic>
          ? decoded
          : Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      return null;
    }
  }

  static String? _string(Object? value, {required int maxLength}) {
    if (value is! String) return null;
    final result = value.trim();
    if (result.isEmpty) return null;
    return result.length <= maxLength ? result : result.substring(0, maxLength);
  }

  static double? _positiveNumber(Object? value) {
    final number = switch (value) {
      num number => number.toDouble(),
      String text => _parseLocalizedNumber(text),
      _ => null,
    };
    if (number == null) return null;
    if (!number.isFinite || number <= 0 || number > _maxMoney) return null;
    return number;
  }

  /// Parses common receipt formats such as `1,250.50`, `1 250,50`, and
  /// `237,60 MAD`. The previous implementation removed commas unconditionally,
  /// turning the last example into 23,760 and causing valid AI results to be
  /// rejected or displayed incorrectly.
  static double? _parseLocalizedNumber(String text) {
    final match = RegExp(r'[-+]?\d[\d\s.,]*').firstMatch(text);
    if (match == null) return null;

    var value = match.group(0)!.replaceAll(RegExp(r'\s'), '');
    final comma = value.lastIndexOf(',');
    final dot = value.lastIndexOf('.');

    if (comma >= 0 && dot >= 0) {
      if (comma > dot) {
        value = value.replaceAll('.', '').replaceFirst(',', '.');
      } else {
        value = value.replaceAll(',', '');
      }
    } else if (comma >= 0) {
      final decimalDigits = value.length - comma - 1;
      value = decimalDigits > 0 && decimalDigits <= 2
          ? value.replaceFirst(',', '.')
          : value.replaceAll(',', '');
    }

    return double.tryParse(value);
  }

  static int? _positiveInt(Object? value) {
    final number = switch (value) {
      num value => value.toDouble(),
      String text => double.tryParse(text.trim()),
      _ => null,
    };
    if (number == null || !number.isFinite || number <= 0 || number > 100000) {
      return null;
    }
    final integer = number.toInt();
    return number == integer ? integer : null;
  }

  static String? _category(Object? value) {
    if (value is! String) return null;
    switch (value.trim().toLowerCase()) {
      case 'software':
      case 'software / saas':
      case 'logiciel':
      case 'logiciels':
        return 'software';
      case 'travel':
      case 'transport':
      case 'transportation':
      case 'voyage':
        return 'travel';
      case 'office':
      case 'office supplies':
      case 'fournitures de bureau':
      case 'bureau':
        return 'office';
      case 'marketing':
      case 'advertising':
      case 'publicité':
        return 'marketing';
      case 'meals':
      case 'meal':
      case 'food':
      case 'meals and entertainment':
      case 'restaurant':
      case 'food and beverage':
      case 'alimentation':
      case 'repas':
        return 'meals';
      case 'other':
        return 'other';
      default:
        // Unknown categories are safe to place in the user's "Other" bucket;
        // the user still verifies the value before saving.
        return value.trim().isEmpty ? null : 'other';
    }
  }
}
