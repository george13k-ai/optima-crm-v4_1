import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class QwenXmlService {
  QwenXmlService._();

  static final QwenXmlService instance = QwenXmlService._();

  static const String _apiKey = String.fromEnvironment('QWEN_API_KEY');
  static const String _apiBaseUrl = String.fromEnvironment(
    'QWEN_API_BASE_URL',
    defaultValue: 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
  );
  static const String _model = String.fromEnvironment(
    'QWEN_MODEL',
    defaultValue: 'qwen-plus',
  );

  Future<String?> tryNormalizePayload(String payload) async {
    if (_apiKey.trim().isEmpty) return null;

    try {
      final response = await Dio().post<Map<String, dynamic>>(
        '$_apiBaseUrl/chat/completions',
        data: {
          'model': _model,
          'response_format': {'type': 'json_object'},
          'temperature': 0,
          'messages': [
            {
              'role': 'system',
              'content':
                  'You convert order payload into strict JSON. '
                      'Return JSON only with keys: clientName, paymentStatus, comment, lines. '
                      'lines is array of objects {lookup, quantity}. '
                      'quantity must be positive integer. '
                      'Ignore unknown fields.',
            },
            {
              'role': 'user',
              'content': 'Payload:\n$payload',
            },
          ],
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 25),
        ),
      );

      final content = _extractContent(response.data);
      if (content == null || content.trim().isEmpty) return null;
      final normalized = _buildTablePayloadFromJson(content);
      if (normalized == null || normalized.trim().isEmpty) return null;
      return normalized;
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> tryNormalizeBinarySpreadsheet({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (_apiKey.trim().isEmpty) return null;

    final base64Data = base64Encode(bytes);
    final ext = fileName.toLowerCase().endsWith('.xls') ? 'xls' : 'xlsx';
    final prompt = 'File name: $fileName\n'
        'Format: $ext\n'
        'Base64 bytes:\n$base64Data\n'
        'Extract order lines and return JSON with keys: clientName, paymentStatus, comment, lines[{lookup,quantity}]';
    return tryNormalizePayload(prompt);
  }

  String? _extractContent(Map<String, dynamic>? root) {
    if (root == null) return null;
    final choices = root['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map<String, dynamic>) return null;
    final message = first['message'];
    if (message is! Map<String, dynamic>) return null;
    final content = message['content'];
    if (content is String) return content;
    if (content is List) {
      final textPart = content
          .whereType<Map<String, dynamic>>()
          .map((part) => part['text'])
          .whereType<String>()
          .join('\n');
      return textPart.isEmpty ? null : textPart;
    }
    return null;
  }

  String? _buildTablePayloadFromJson(String rawJson) {
    final sanitized = _extractJsonObject(rawJson) ?? rawJson;
    final decoded = jsonDecode(sanitized);
    if (decoded is! Map<String, dynamic>) return null;

    final linesNode = decoded['lines'];
    if (linesNode is! List || linesNode.isEmpty) return null;

    final clientName = (decoded['clientName'] ?? '').toString().trim();
    final paymentStatus = (decoded['paymentStatus'] ?? '').toString().trim();
    final comment = (decoded['comment'] ?? '').toString().trim();

    final rows = <String>[
      'Client\tPayment\tComment\tProduct\tQty',
    ];

    for (final row in linesNode) {
      if (row is! Map<String, dynamic>) continue;
      final lookup = (row['lookup'] ?? '').toString().trim();
      final quantityRaw = row['quantity'];
      final quantity = int.tryParse(quantityRaw.toString());
      if (lookup.isEmpty || quantity == null || quantity <= 0) continue;

      rows.add(
        '${_safeCell(clientName)}\t${_safeCell(paymentStatus)}\t${_safeCell(comment)}\t${_safeCell(lookup)}\t$quantity',
      );
    }

    return rows.length > 1 ? rows.join('\n') : null;
  }

  String _safeCell(String value) => value
      .replaceAll('\t', ' ')
      .replaceAll('\n', ' ')
      .replaceAll('\r', ' ')
      .trim();

  String? _extractJsonObject(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return raw.substring(start, end + 1);
  }
}
