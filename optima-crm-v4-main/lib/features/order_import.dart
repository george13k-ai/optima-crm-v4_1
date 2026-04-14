import 'dart:convert';

import 'package:crm/domain/entities/entities.dart';
import 'package:xml/xml.dart';

class ImportedOrderLine {
  const ImportedOrderLine({
    required this.lookup,
    required this.quantity,
    this.salePrice,
    this.purchasePrice,
  });

  final String lookup;
  final int quantity;
  /// Sale price extracted from the table (null if not present).
  final double? salePrice;
  /// Purchase / cost price extracted from the table (null if not present).
  final double? purchasePrice;
}

class ImportedOrderData {
  const ImportedOrderData({
    required this.lines,
    this.clientName,
    this.paymentStatus,
    this.comment,
  });

  final List<ImportedOrderLine> lines;
  final String? clientName;
  final PaymentStatus? paymentStatus;
  final String? comment;
}

ImportedOrderData parseImportedOrder(String raw) {
  final normalizedRaw = raw.trim();
  if (normalizedRaw.isEmpty) {
    throw const FormatException('Сначала вставьте строки из таблицы.');
  }

  if (_looksLikeOrderXml(normalizedRaw)) {
    final xmlResult = _tryParseImportedOrderXml(normalizedRaw);
    if (xmlResult != null) return xmlResult;
  }

  final rows = normalizedRaw
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (rows.isEmpty) {
    throw const FormatException(
      'Во вставленных данных не найдено ни одной строки.',
    );
  }

  final delimiter = _detectDelimiterFromRows(rows);
  final headerIndex = _findHeaderRowIndex(rows, delimiter);
  final headerCells = headerIndex == null
      ? const <String>[]
      : _splitRow(rows[headerIndex], delimiter);
  final hasHeader = headerIndex != null;
  final headers = hasHeader
      ? headerCells.map(_normalizeHeaderKey).toList(growable: false)
      : const <String>[];
  final dataRows = hasHeader ? rows.skip(headerIndex + 1) : rows;

  final lines = <ImportedOrderLine>[];
  final parsedDataRows = <List<String>>[];
  String? clientName;
  PaymentStatus? paymentStatus;
  String? comment;

  for (final row in dataRows) {
    final cells = _splitRow(row, delimiter);
    if (cells.every((cell) => cell.isEmpty)) continue;
    parsedDataRows.add(cells);

    if (hasHeader) {
      final map = <String, String>{};
      for (var i = 0; i < headers.length && i < cells.length; i++) {
        map[headers[i]] = cells[i];
      }

      clientName ??= _readMappedValue(map, const [
        'client',
        'clientname',
        'company',
        'customer',
        'buyer',
        'клиент',
        'контрагент',
        'компания',
        'покупатель',
        'заказчик',
      ]);
      paymentStatus ??= _parsePaymentStatus(
        _readMappedValue(map, const [
          'payment',
          'paymentstatus',
          'paid',
          'status',
          'оплата',
          'статус',
          'оплачено',
        ]),
      );
      comment ??= _readMappedValue(map, const [
        'comment',
        'note',
        'notes',
        'remark',
        'memo',
        'комментарий',
        'примечание',
        'заметка',
      ]);

      final lookup = _readMappedValue(map, const [
        'sku',
        'vendorcode',
        'article',
        'code',
        'productcode',
        'product',
        'productname',
        'goodsname',
        'goods',
        'name',
        'title',
        'item',
        'номенклатура',
        'наименование',
        'название',
        'товар',
        'артикул',
        'код',
      ]);
      final quantityValue = _readMappedValue(map, const [
        'qty',
        'quantity',
        'count',
        'pcs',
        'pieces',
        'number',
        'колво',
        'кол',
        'количество',
        'шт',
      ]);
      final salePriceValue = _readMappedValue(map, const [
        'price',
        'saleprice',
        'retail',
        'retailprice',
        'sellingprice',
        'цена',
        'розница',
        'розничная',
        'ценапродажи',
        'стоимость',
        'сумма',
        'суммазаказа',
        'итого',
      ]);
      final purchasePriceValue = _readMappedValue(map, const [
        'cost',
        'purchaseprice',
        'wholesale',
        'wholesaleprice',
        'закупка',
        'закупочная',
        'себестоимость',
        'ценазакупки',
        'себест',
      ]);
      final quantity = _parseQuantity(quantityValue);
      if (lookup != null &&
          quantity != null &&
          quantity > 0 &&
          _looksLikeLookupCell(lookup)) {
        lines.add(ImportedOrderLine(
          lookup: lookup,
          quantity: quantity,
          salePrice: _parsePrice(salePriceValue),
          purchasePrice: _parsePrice(purchasePriceValue),
        ));
      }
      continue;
    }

    final inferred = _inferLineFromRow(cells);
    if (inferred != null) {
      lines.add(inferred);
    }
  }

  if (lines.isEmpty && hasHeader && !_hasOrderColumns(headers)) {
    lines.addAll(_inferLinesFromUnknownColumns(parsedDataRows, headers));
  }

  if (lines.isEmpty && hasHeader && !_hasOrderColumns(headers)) {
    throw const FormatException(
      'В найденных колонках нет полей "Товар/SKU" и "Количество". Этот лист не подходит для импорта заказа.',
    );
  }

  if (lines.isEmpty) {
    throw const FormatException(
      'Не удалось распознать строки товаров. Нужны колонки "Товар/SKU" и "Количество".',
    );
  }

  return ImportedOrderData(
    lines: lines,
    clientName: clientName,
    paymentStatus: paymentStatus,
    comment: comment,
  );
}

const _xmlLookupAliases = <String>[
  'sku',
  'code',
  'product',
  'productname',
  'name',
  'item',
  'good',
  'article',
  'vendorcode',
  'vendor_code',
  'product_code',
  'productsku',
  'product_sku',
  'title',
  'товар',
  'наименование',
  'номенклатура',
  'артикул',
];

const _xmlQuantityAliases = <String>[
  'qty',
  'quantity',
  'count',
  'pieces',
  'piece',
  'pcs',
  'qnt',
  'number',
  'количество',
  'шт',
];

const _xmlSalePriceAliases = <String>[
  'price',
  'saleprice',
  'retail',
  'retailprice',
  'sellingprice',
  'цена',
  'розница',
  'розничная',
  'ценапродажи',
  'стоимость',
  'сумма',
  'суммазаказа',
  'итого',
];

const _xmlPurchasePriceAliases = <String>[
  'cost',
  'purchaseprice',
  'wholesale',
  'wholesaleprice',
  'закупка',
  'закупочная',
  'себестоимость',
  'ценазакупки',
  'себест',
];

const _xmlClientAliases = <String>[
  'client',
  'clientname',
  'customer',
  'buyer',
  'company',
  'account',
  'клиент',
  'контрагент',
  'компания',
];

const _xmlPaymentAliases = <String>[
  'payment',
  'paymentstatus',
  'status',
  'paid',
  'ispaid',
  'оплата',
  'статусоплаты',
];

const _xmlCommentAliases = <String>[
  'comment',
  'note',
  'notes',
  'description',
  'remark',
  'memo',
  'комментарий',
  'примечание',
];

Uri? googleSheetsCsvUri(String raw) {
  final urls = googleSheetsCsvUris(raw);
  return urls.isEmpty ? null : urls.first;
}

List<Uri> googleSheetsCsvUris(String raw) {
  final input = raw.trim();
  if (input.isEmpty) return const [];

  final uri = _parseGoogleLikeUri(input);
  if (uri == null || !uri.hasScheme) return const [];
  final host = uri.host.toLowerCase();
  if (!host.contains('docs.google.com') && !host.contains('drive.google.com')) {
    return const [];
  }

  final gid = _extractGid(uri);
  final segments = uri.pathSegments;

  final publishedIndex = segments.indexOf('e');
  if (publishedIndex >= 0 && publishedIndex + 1 < segments.length) {
    final publishedId = segments[publishedIndex + 1];
    if (publishedId.isEmpty) return const [];
    return [
      Uri.https('docs.google.com', '/spreadsheets/d/e/$publishedId/pub', {
        'output': 'csv',
        if (gid != null && gid.isNotEmpty) 'gid': gid,
      }),
      Uri.https('docs.google.com', '/spreadsheets/d/e/$publishedId/pub', {
        'output': 'tsv',
        if (gid != null && gid.isNotEmpty) 'gid': gid,
      }),
    ];
  }

  final documentId = _extractGoogleSheetDocumentId(uri);
  if (documentId.isEmpty) return const [];

  return [
    Uri.https('docs.google.com', '/spreadsheets/d/$documentId/export', {
      'format': 'csv',
      if (gid != null && gid.isNotEmpty) 'gid': gid,
    }),
    Uri.https('docs.google.com', '/spreadsheets/d/$documentId/export', {
      'format': 'csv',
      'single': 'true',
      if (gid != null && gid.isNotEmpty) 'gid': gid,
    }),
    Uri.https('docs.google.com', '/spreadsheets/d/$documentId/gviz/tq', {
      'tqx': 'out:csv',
      if (gid != null && gid.isNotEmpty) 'gid': gid,
    }),
    Uri.https('docs.google.com', '/spreadsheets/d/$documentId/gviz/tq', {
      'tqx': 'out:json',
      if (gid != null && gid.isNotEmpty) 'gid': gid,
    }),
    Uri.https('docs.google.com', '/spreadsheets/d/$documentId/export', {
      'format': 'tsv',
      if (gid != null && gid.isNotEmpty) 'gid': gid,
    }),
    Uri.https('docs.google.com', '/feeds/download/spreadsheets/Export', {
      'key': documentId,
      'exportFormat': 'csv',
      if (gid != null && gid.isNotEmpty) 'gid': gid,
    }),
  ];
}

String? normalizeImportedTablePayload(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  // Reject Google sign-in / access-denied HTML pages before any parsing
  if (_looksLikeGoogleErrorPage(text)) return null;

  final fromGviz = _parseGoogleVisualizationBody(text);
  if (fromGviz != null && fromGviz.trim().isNotEmpty) return fromGviz.trim();

  final fromHtml = _parseHtmlTableBody(text);
  if (fromHtml != null && fromHtml.trim().isNotEmpty) return fromHtml.trim();

  return text;
}

bool _looksLikeGoogleErrorPage(String body) {
  final lower = body.toLowerCase();
  if (!lower.contains('<html') && !lower.contains('<!doctype')) return false;
  if (lower.contains('accounts.google.com')) return true;
  if (lower.contains('servicelogin')) return true;
  if (lower.contains('gaia_loginform')) return true;
  if (lower.contains('access denied') || lower.contains('access_denied')) {
    return true;
  }
  if (lower.contains('sign in') && lower.contains('google')) return true;
  return false;
}

Product? findMatchingProduct(List<Product> products, String lookup) {
  final normalized = _normalizeToken(lookup);
  if (normalized.isEmpty) return null;

  for (final product in products) {
    final sku = _normalizeToken(product.sku ?? '');
    final name = _normalizeToken(product.name);
    if (sku == normalized || name == normalized) return product;
  }
  for (final product in products) {
    final sku = _normalizeToken(product.sku ?? '');
    final name = _normalizeToken(product.name);
    if (sku.contains(normalized) || name.contains(normalized)) return product;
  }
  return null;
}

Client? findMatchingClient(List<Client> clients, String? lookup) {
  if (lookup == null || lookup.trim().isEmpty) return null;
  final normalized = _normalizeToken(lookup);
  for (final client in clients) {
    if (_normalizeToken(client.name) == normalized) return client;
  }
  for (final client in clients) {
    if (_normalizeToken(client.name).contains(normalized)) return client;
  }
  return null;
}

bool _looksLikeOrderXml(String text) {
  final lower = text.trimLeft().toLowerCase();
  if (!lower.startsWith('<') && !lower.startsWith('<?xml')) return false;
  if (lower.startsWith('<!doctype html') || lower.startsWith('<html')) {
    return false;
  }
  return lower.contains('<') && lower.contains('>');
}

ImportedOrderData? _tryParseImportedOrderXml(String raw) {
  try {
    final document = XmlDocument.parse(raw);
    final lines = _extractXmlLines(document);
    if (lines.isEmpty) return null;

    final clientName = _findFirstXmlValue(document, _xmlClientAliases);
    final paymentStatus = _parsePaymentStatus(
      _findFirstXmlValue(document, _xmlPaymentAliases),
    );
    final comment = _findFirstXmlValue(document, _xmlCommentAliases);

    return ImportedOrderData(
      lines: lines,
      clientName: clientName,
      paymentStatus: paymentStatus,
      comment: comment,
    );
  } catch (_) {
    return null;
  }
}

List<ImportedOrderLine> _extractXmlLines(XmlDocument document) {
  final lines = <ImportedOrderLine>[];
  // Deduplicate only by (lookup, quantity, position) — allow same product
  // with same qty if it appears in distinct XML elements (real separate lines).
  // We use a simple seen-set keyed by element identity to avoid re-visiting
  // the same logical node via ancestor traversal, but allow truly distinct rows.
  final seenElements = <XmlElement>{};

  for (final element in document.descendants.whereType<XmlElement>()) {
    if (!seenElements.add(element)) continue;
    final map = _xmlElementToFieldMap(element);
    final lookup = _readMappedValue(map, _xmlLookupAliases);
    final quantity = _parseQuantity(_readMappedValue(map, _xmlQuantityAliases));
    if (lookup == null ||
        lookup.trim().isEmpty ||
        quantity == null ||
        quantity <= 0 ||
        !_looksLikeLookupCell(lookup)) {
      continue;
    }

    lines.add(ImportedOrderLine(
      lookup: lookup.trim(),
      quantity: quantity,
      salePrice: _parsePrice(_readMappedValue(map, _xmlSalePriceAliases)),
      purchasePrice:
          _parsePrice(_readMappedValue(map, _xmlPurchasePriceAliases)),
    ));
  }

  return lines;
}

Map<String, String> _xmlElementToFieldMap(XmlElement element) {
  final map = <String, String>{};

  for (final attr in element.attributes) {
    final key = _normalizeXmlName(attr.name.local);
    if (!map.containsKey(key) && attr.value.trim().isNotEmpty) {
      map[key] = attr.value.trim();
    }
  }

  for (final child in element.childElements) {
    final key = _normalizeXmlName(child.name.local);
    final value = _extractXmlText(child);
    if (!map.containsKey(key) && value.isNotEmpty) {
      map[key] = value;
    }
  }

  return map;
}

String? _findFirstXmlValue(XmlDocument doc, List<String> aliases) {
  for (final element in doc.descendants.whereType<XmlElement>()) {
    final normalizedName = _normalizeXmlName(element.name.local);
    if (!aliases.contains(normalizedName)) continue;
    final value = _extractXmlText(element);
    if (value.isNotEmpty) return value;
  }
  return null;
}

String _extractXmlText(XmlElement element) {
  final text = element.innerText.trim();
  if (text.isEmpty) return '';
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _normalizeXmlName(String value) => value
    .toLowerCase()
    .replaceAll('-', '')
    .replaceAll('_', '')
    .replaceAll(RegExp(r'[^a-zа-яё0-9]'), '')
    .trim();

String _detectDelimiter(String row) {
  final tabCount = '\t'.allMatches(row).length;
  final semicolonCount = ';'.allMatches(row).length;
  final commaCount = ','.allMatches(row).length;
  if (tabCount >= semicolonCount && tabCount >= commaCount && tabCount > 0) {
    return '\t';
  }
  if (semicolonCount >= commaCount && semicolonCount > 0) {
    return ';';
  }
  return ',';
}

String _detectDelimiterFromRows(List<String> rows) {
  if (rows.isEmpty) return ',';
  final sample = rows.take(8);
  var tab = 0;
  var semicolon = 0;
  var comma = 0;

  for (final row in sample) {
    tab += '\t'.allMatches(row).length;
    semicolon += ';'.allMatches(row).length;
    comma += ','.allMatches(row).length;
  }

  if (tab >= semicolon && tab >= comma && tab > 0) return '\t';
  if (semicolon >= comma && semicolon > 0) return ';';
  if (comma > 0) return ',';
  return _detectDelimiter(rows.first);
}

int? _findHeaderRowIndex(List<String> rows, String delimiter) {
  final maxIndex = rows.length > 20 ? 20 : rows.length;
  for (var i = 0; i < maxIndex; i++) {
    final cells = _splitRow(rows[i], delimiter);
    if (_looksLikeHeader(cells)) return i;
  }
  return null;
}

String? _extractGid(Uri uri) {
  final gidFromQuery = uri.queryParameters['gid'];
  if (gidFromQuery != null && gidFromQuery.isNotEmpty) return gidFromQuery;

  final fragment = uri.fragment;
  if (fragment.contains('gid=')) {
    final gid = fragment.split('gid=').last.split('&').first;
    if (gid.isNotEmpty) return gid;
  }
  return null;
}

Uri? _parseGoogleLikeUri(String input) {
  final trimmed = input.trim();
  final parsed = Uri.tryParse(trimmed);
  if (parsed != null && parsed.hasScheme) return parsed;

  if (trimmed.startsWith('docs.google.com/') ||
      trimmed.startsWith('drive.google.com/')) {
    return Uri.tryParse('https://$trimmed');
  }
  if (trimmed.startsWith('//docs.google.com/') ||
      trimmed.startsWith('//drive.google.com/')) {
    return Uri.tryParse('https:$trimmed');
  }
  return parsed;
}

String _extractGoogleSheetDocumentId(Uri uri) {
  final segments = uri.pathSegments;

  final docIndex = segments.indexOf('d');
  if (docIndex >= 0 && docIndex + 1 < segments.length) {
    return segments[docIndex + 1];
  }

  final queryId = uri.queryParameters['id'];
  if (queryId != null && queryId.isNotEmpty) return queryId;

  return '';
}

/// Finds the index of the closing `)` that matches the `(` at [openPos].
/// Skips characters inside JSON string literals to avoid false matches.
int _findMatchingCloseParen(String body, int openPos) {
  var depth = 0;
  var inString = false;
  var escape = false;
  for (var i = openPos; i < body.length; i++) {
    final c = body[i];
    if (escape) {
      escape = false;
      continue;
    }
    if (c == '\\' && inString) {
      escape = true;
      continue;
    }
    if (c == '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

String? _parseGoogleVisualizationBody(String body) {
  const marker = 'google.visualization.Query.setResponse(';
  final markerIndex = body.indexOf(marker);
  if (markerIndex < 0) return null;

  // openPos points at the '(' character
  final openPos = markerIndex + marker.length - 1;
  final closePos = _findMatchingCloseParen(body, openPos);
  if (closePos < openPos) return null;

  final payload = body.substring(openPos + 1, closePos).trim();
  if (payload.isEmpty) return null;

  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) return null;
    final table = decoded['table'];
    if (table is! Map<String, dynamic>) return null;

    final cols = table['cols'];
    final rows = table['rows'];
    if (rows is! List || rows.isEmpty) return null;

    final resultRows = <String>[];
    if (cols is List) {
      final headers = cols
          .map((col) {
            if (col is! Map<String, dynamic>) return '';
            return (col['label'] ?? col['id'] ?? '').toString().trim();
          })
          .toList(growable: false);
      if (headers.any((header) => header.isNotEmpty)) {
        resultRows.add(
          headers.map((v) => v.replaceAll('\t', ' ').trim()).join('\t'),
        );
      }
    }

    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final cells = row['c'];
      if (cells is! List) continue;

      final normalizedCells = cells
          .map((cell) {
            if (cell is! Map<String, dynamic>) return '';
            final value = (cell['f'] ?? cell['v'] ?? '').toString();
            return value.replaceAll('\t', ' ').replaceAll('\n', ' ').trim();
          })
          .toList(growable: false);

      resultRows.add(normalizedCells.join('\t'));
    }

    final output = resultRows.join('\n').trim();
    return output.isEmpty ? null : output;
  } catch (_) {
    return null;
  }
}

String? _parseHtmlTableBody(String body) {
  final lower = body.toLowerCase();
  if (!lower.contains('<table') ||
      (!lower.contains('<td') && !lower.contains('<th'))) {
    return null;
  }

  final rowMatches = RegExp(
    r'<tr[^>]*>([\s\S]*?)</tr>',
    caseSensitive: false,
  ).allMatches(body);
  if (rowMatches.isEmpty) return null;

  final parsedRows = <String>[];
  for (final rowMatch in rowMatches) {
    final rowHtml = rowMatch.group(1);
    if (rowHtml == null || rowHtml.isEmpty) continue;

    final cellMatches = RegExp(
      r'<t[hd][^>]*>([\s\S]*?)</t[hd]>',
      caseSensitive: false,
    ).allMatches(rowHtml);
    if (cellMatches.isEmpty) continue;

    final cells = cellMatches
        .map((cellMatch) => _stripHtml(cellMatch.group(1) ?? ''))
        .map(
          (value) => value.replaceAll('\t', ' ').replaceAll('\n', ' ').trim(),
        )
        .toList(growable: false);
    if (cells.every((cell) => cell.isEmpty)) continue;
    parsedRows.add(cells.join('\t'));
  }

  if (parsedRows.isEmpty) return null;
  return parsedRows.join('\n');
}

String _stripHtml(String raw) {
  final withNewLines = raw
      .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</\s*p\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</\s*div\s*>', caseSensitive: false), '\n');
  final noTags = withNewLines.replaceAll(RegExp(r'<[^>]+>'), ' ');
  return noTags
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

List<String> _splitRow(String row, String delimiter) {
  if (row.isEmpty) return const [''];

  final cells = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < row.length; i++) {
    final char = row[i];
    final isQuote = char == '"';

    if (isQuote) {
      final nextIsQuote = i + 1 < row.length && row[i + 1] == '"';
      if (inQuotes && nextIsQuote) {
        buffer.write('"');
        i++;
        continue;
      }
      inQuotes = !inQuotes;
      continue;
    }

    if (!inQuotes && char == delimiter) {
      cells.add(buffer.toString().trim());
      buffer.clear();
      continue;
    }

    buffer.write(char);
  }

  cells.add(buffer.toString().trim());
  return cells;
}

bool _looksLikeHeader(List<String> cells) {
  final joined = cells.map(_normalizeHeaderKey).join('|');
  return joined.contains('product') ||
      joined.contains('goods') ||
      joined.contains('sku') ||
      joined.contains('article') ||
      joined.contains('vendorcode') ||
      joined.contains('qty') ||
      joined.contains('quantity') ||
      joined.contains('amount') ||
      joined.contains('client') ||
      joined.contains('customer') ||
      joined.contains('наименование') ||
      joined.contains('название') ||
      joined.contains('номенклатура') ||
      joined.contains('товар') ||
      joined.contains('артикул') ||
      joined.contains('клиент') ||
      joined.contains('количество') ||
      joined.contains('колво') ||
      joined.contains('кол');
}

bool _hasOrderColumns(List<String> headers) {
  bool headerContains(String keyword) =>
      headers.any((h) => h == keyword || h.contains(keyword));
  final hasProduct =
      headerContains('product') ||
      headerContains('goods') ||
      headerContains('sku') ||
      headerContains('article') ||
      headerContains('vendorcode') ||
      headerContains('code') ||
      headerContains('name') ||
      headerContains('item') ||
      headerContains('title') ||
      headerContains('номенклатура') ||
      headerContains('наименование') ||
      headerContains('название') ||
      headerContains('товар') ||
      headerContains('артикул') ||
      headerContains('код');
  final hasQty =
      headerContains('qty') ||
      headerContains('quantity') ||
      headerContains('amount') ||
      headerContains('count') ||
      headerContains('pcs') ||
      headerContains('pieces') ||
      headerContains('number') ||
      headerContains('количество') ||
      headerContains('колво') ||
      headerContains('кол') ||
      headerContains('шт');
  return hasProduct && hasQty;
}

String? _readMappedValue(Map<String, String> map, List<String> aliases) {
  // 1. Exact match
  for (final alias in aliases) {
    final value = map[alias];
    if (value != null && value.trim().isNotEmpty) return value.trim();
  }
  // 2. Partial match: normalized key contains alias
  //    Handles "Наименование товара"→"наименованиетовара" matching alias "наименование"
  //    Handles "Кол-во"→"колво" matching alias "колво" or "кол"
  for (final alias in aliases) {
    for (final entry in map.entries) {
      if (entry.key.contains(alias) && entry.value.trim().isNotEmpty) {
        return entry.value.trim();
      }
    }
  }
  return null;
}

List<ImportedOrderLine> _inferLinesFromUnknownColumns(
  List<List<String>> rows,
  List<String> headers,
) {
  if (rows.isEmpty) return const <ImportedOrderLine>[];

  var maxCols = 0;
  for (final row in rows) {
    if (row.length > maxCols) maxCols = row.length;
  }
  if (maxCols == 0) return const <ImportedOrderLine>[];

  final numericCounts = List<int>.filled(maxCols, 0);
  final textCounts = List<int>.filled(maxCols, 0);

  for (final row in rows) {
    for (var i = 0; i < row.length; i++) {
      final cell = row[i].trim();
      if (cell.isEmpty) continue;
      if (_parseQuantity(cell) != null) {
        numericCounts[i]++;
      }
      if (_looksLikeLookupCell(cell)) {
        textCounts[i]++;
      }
    }
  }

  var qtyCol = _findQtyColumnByHeader(headers, numericCounts);
  qtyCol = qtyCol >= 0 ? qtyCol : _indexOfMax(numericCounts);

  final hasReliableQtyColumn =
      qtyCol >= 0 &&
      (_isLikelyQuantityHeader(
            qtyCol < headers.length ? headers[qtyCol] : '',
          ) ||
          rows.length >= 2);
  if (!hasReliableQtyColumn) {
    return const <ImportedOrderLine>[];
  }

  var lookupCol = _findLookupColumnByHeader(
    headers: headers,
    textCounts: textCounts,
    exceptIndex: qtyCol,
  );
  lookupCol = lookupCol >= 0
      ? lookupCol
      : _indexOfMax(textCounts, exceptIndex: qtyCol);

  if (lookupCol < 0 || qtyCol < 0) {
    return rows
        .map(_inferLineFromRow)
        .whereType<ImportedOrderLine>()
        .toList(growable: false);
  }

  // Find price column: prefer explicit price header, else first numeric column
  // that's not the qty column and looks like prices (values > 1 on average).
  int priceCol = -1;
  for (var i = 0; i < headers.length; i++) {
    if (i == qtyCol || i == lookupCol) continue;
    if (_isLikelyPriceHeader(headers[i])) {
      priceCol = i;
      break;
    }
  }
  if (priceCol < 0) {
    // fallback: pick numeric column with largest average value (prices > qty)
    var bestAvg = 1.0;
    for (var i = 0; i < maxCols; i++) {
      if (i == qtyCol || i == lookupCol) continue;
      var sum = 0.0;
      var cnt = 0;
      for (final row in rows) {
        final v = _parsePrice(i < row.length ? row[i] : null);
        if (v != null && v > 0) { sum += v; cnt++; }
      }
      if (cnt > 0 && sum / cnt > bestAvg) {
        bestAvg = sum / cnt;
        priceCol = i;
      }
    }
  }

  final lines = <ImportedOrderLine>[];
  for (final row in rows) {
    final lookup = lookupCol < row.length ? row[lookupCol].trim() : '';
    final qtyRaw = qtyCol < row.length ? row[qtyCol] : '';
    final qty = _parseQuantity(qtyRaw);
    final lookupHeader = lookupCol < headers.length ? headers[lookupCol] : '';
    if (_isLikelyMetaHeader(lookupHeader)) continue;

    if (lookup.isNotEmpty &&
        qty != null &&
        qty > 0 &&
        _looksLikeLookupCell(lookup)) {
      final priceRaw = priceCol >= 0 && priceCol < row.length ? row[priceCol] : null;
      lines.add(ImportedOrderLine(
        lookup: lookup,
        quantity: qty,
        salePrice: _parsePrice(priceRaw),
      ));
    }
  }

  if (lines.isNotEmpty) return lines;
  return rows
      .map(_inferLineFromRow)
      .whereType<ImportedOrderLine>()
      .toList(growable: false);
}

ImportedOrderLine? _inferLineFromRow(List<String> cells) {
  if (cells.isEmpty) return null;

  var qtyIndex = -1;
  for (var i = cells.length - 1; i >= 0; i--) {
    if (_parseQuantity(cells[i]) != null) {
      qtyIndex = i;
      break;
    }
  }
  if (qtyIndex < 0) return null;

  final qty = _parseQuantity(cells[qtyIndex]);
  if (qty == null || qty <= 0) return null;

  String? lookup;
  for (var i = 0; i < cells.length; i++) {
    if (i == qtyIndex) continue;
    final value = cells[i].trim();
    if (!_looksLikeLookupCell(value)) continue;
    lookup = value;
    break;
  }
  if (lookup == null || lookup.isEmpty) return null;

  return ImportedOrderLine(lookup: lookup, quantity: qty);
}

bool _looksLikeLookupCell(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return false;
  if (normalized.length <= 1) return false;
  if (!RegExp(r'[a-zA-Zа-яА-ЯёЁ0-9]').hasMatch(normalized)) return false;
  if (_isLikelySummaryLookup(normalized)) return false;
  if (_parseQuantity(normalized) != null &&
      !RegExp(r'[a-zA-Zа-яА-ЯёЁ]').hasMatch(normalized)) {
    return false;
  }
  return true;
}

bool _isLikelySummaryLookup(String value) {
  final key = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-zа-яё0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (key.isEmpty) return true;
  final headerKey = _normalizeHeaderKey(value);
  if (_isLikelyQuantityHeader(headerKey) || _isLikelyPriceHeader(headerKey)) {
    return true;
  }

  const exact = <String>{
    'итого',
    'всего',
    'итог',
    'subtotal',
    'total',
    'grand total',
    'summary',
    'sum',
    'сумма',
    'результат',
  };
  if (exact.contains(key)) return true;

  final words = key
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList(growable: false);
  const summaryWords = <String>{
    'итого',
    'всего',
    'итог',
    'total',
    'subtotal',
    'grand',
    'summary',
    'sum',
    'сумма',
    'result',
    'qty',
    'quantity',
    'amount',
    'шт',
    'количество',
    'кол',
    'колво',
  };
  if (words.isNotEmpty && words.every(summaryWords.contains)) return true;

  final startsWithSummary =
      key.startsWith('итого') ||
      key.startsWith('всего') ||
      key.startsWith('итог') ||
      key.startsWith('total') ||
      key.startsWith('subtotal') ||
      key.startsWith('grand total');
  if (startsWithSummary) return true;

  return false;
}

int _indexOfMax(List<int> values, {int exceptIndex = -1}) {
  var bestIndex = -1;
  var bestValue = -1;
  for (var i = 0; i < values.length; i++) {
    if (i == exceptIndex) continue;
    if (values[i] > bestValue) {
      bestValue = values[i];
      bestIndex = i;
    }
  }
  return bestValue > 0 ? bestIndex : -1;
}

int _findQtyColumnByHeader(List<String> headers, List<int> numericCounts) {
  var bestIndex = -1;
  var bestNumeric = -1;
  for (var i = 0; i < headers.length && i < numericCounts.length; i++) {
    if (!_isLikelyQuantityHeader(headers[i])) continue;
    if (numericCounts[i] > bestNumeric) {
      bestNumeric = numericCounts[i];
      bestIndex = i;
    }
  }
  return bestIndex;
}

int _findLookupColumnByHeader({
  required List<String> headers,
  required List<int> textCounts,
  required int exceptIndex,
}) {
  var bestIndex = -1;
  var bestScore = -9999;

  for (var i = 0; i < textCounts.length; i++) {
    if (i == exceptIndex) continue;
    if (textCounts[i] <= 0) continue;

    final header = i < headers.length ? headers[i] : '';
    var score = textCounts[i];
    if (_isLikelyProductHeader(header)) score += 5;
    if (_isLikelyMetaHeader(header)) score -= 6;
    if (_isLikelyPriceHeader(header)) score -= 6;

    if (score > bestScore) {
      bestScore = score;
      bestIndex = i;
    }
  }

  return bestScore > 0 ? bestIndex : -1;
}

bool _isLikelyProductHeader(String header) {
  if (header.isEmpty) return false;
  return header.contains('product') ||
      header.contains('goods') ||
      header.contains('item') ||
      header.contains('sku') ||
      header.contains('article') ||
      header.contains('name') ||
      header.contains('товар') ||
      header.contains('наименование') ||
      header.contains('номенклатура') ||
      header.contains('артикул') ||
      header.contains('позиц');
}

bool _isLikelyQuantityHeader(String header) {
  if (header.isEmpty) return false;
  return header.contains('qty') ||
      header.contains('quantity') ||
      header.contains('amount') ||
      header.contains('count') ||
      header.contains('pcs') ||
      header.contains('pieces') ||
      header.contains('number') ||
      header.contains('количество') ||
      header.contains('колво') ||
      header.contains('кол') ||
      header.contains('шт');
}

bool _isLikelyMetaHeader(String header) {
  if (header.isEmpty) return false;
  return header.contains('client') ||
      header.contains('customer') ||
      header.contains('buyer') ||
      header.contains('company') ||
      header.contains('payment') ||
      header.contains('status') ||
      header.contains('comment') ||
      header.contains('note') ||
      header.contains('date') ||
      header.contains('email') ||
      header.contains('phone') ||
      header.contains('клиент') ||
      header.contains('контрагент') ||
      header.contains('компания') ||
      header.contains('оплата') ||
      header.contains('статус') ||
      header.contains('комментар') ||
      header.contains('дата') ||
      header.contains('почта') ||
      header.contains('телефон');
}

bool _isLikelyPriceHeader(String header) {
  if (header.isEmpty) return false;
  return header.contains('price') ||
      header.contains('cost') ||
      header.contains('amount') ||
      header.contains('sum') ||
      header.contains('цен') ||
      header.contains('стоим') ||
      header.contains('сумм') ||
      header.contains('руб');
}

int? _parseQuantity(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(',', '.');

  // Accept plain counts only: "3", "3 шт", "3pcs", "3 x", "3.0".
  final match = RegExp(
    r'^(\d+)(?:\.0+)?\s*(?:шт|штук|pcs|pieces|pc|x)?(?:[.,;:!?\s]*)$',
  ).firstMatch(normalized);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

PaymentStatus? _parsePaymentStatus(String? value) {
  final normalized = _normalizeToken(value ?? '');
  if (normalized.isEmpty) return null;
  if (normalized.contains('paid') ||
      normalized.contains('оплачен') ||
      normalized.contains('оплачено') ||
      normalized.contains('yes')) {
    return PaymentStatus.paid;
  }
  if (normalized.contains('unpaid') ||
      normalized.contains('pending') ||
      normalized.contains('неоплачен') ||
      normalized.contains('не оплачено') ||
      normalized.contains('no')) {
    return PaymentStatus.unpaid;
  }
  return null;
}

String _normalizeToken(String value) => value
    .toLowerCase()
    .replaceAll('\ufeff', '')
    .replaceAll('\u200b', '')
    .replaceAll('\u200c', '')
    .replaceAll('\u200d', '')
    .replaceAll('\u2060', '')
    .replaceAll(RegExp("[\"'`]+"), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Aggressive normalization for column header keys.
/// Strips everything except Latin letters, Cyrillic letters and digits.
/// "Наименование товара" → "наименованиетовара"
/// "Кол-во"             → "колво"
/// "SKU / Артикул"      → "скуартикул" (latin + cyrillic)
String _normalizeHeaderKey(String value) => value
    .toLowerCase()
    .replaceAll('\ufeff', '')
    .replaceAll('\u200b', '')
    .replaceAll('\u200c', '')
    .replaceAll('\u200d', '')
    .replaceAll('\u2060', '')
    .replaceAll(RegExp(r'[^a-zа-яё0-9]'), '')
    .trim();

/// Parses a price value from a table cell.
/// Handles formats: "1990", "1 990", "1990.50", "1990,50", "1 990 ₽", "1.990,00 руб."
double? _parsePrice(String? value) {
  if (value == null || value.trim().isEmpty) return null;

  // Strip currency symbols, all letters and whitespace — keep digits and . ,
  var s = value
      .trim()
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'[₽$€£¥]'), '')
      .replaceAll(RegExp(r'[a-zA-Zа-яА-ЯёЁ]+'), '')
      .replaceAll(RegExp(r'\s+'), '');

  if (s.isEmpty) return null;

  // Determine decimal separator: if there's a comma followed by ≤2 digits
  // at the end and no dot, treat comma as decimal point (Russian format).
  if (s.contains(',') && !s.contains('.')) {
    final commaIdx = s.lastIndexOf(',');
    final afterComma = s.substring(commaIdx + 1);
    if (afterComma.length <= 2) {
      s = s.replaceAll(',', '.');
    } else {
      // Thousand separator comma (e.g. "1,990")
      s = s.replaceAll(',', '');
    }
  } else {
    // Remove thousand-separator commas before a dot (e.g. "1,990.00")
    s = s.replaceAll(RegExp(r',(?=\d{3})'), '');
    s = s.replaceAll(',', '');
  }

  final result = double.tryParse(s);
  if (result == null || result < 0) return null;
  return result;
}
