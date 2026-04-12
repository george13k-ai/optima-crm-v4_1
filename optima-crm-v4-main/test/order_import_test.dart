import 'package:crm/data/mock_backend.dart';
import 'package:crm/features/order_import.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses tab-separated sheet rows with headers', () async {
    const raw = 'Client\tProduct\tQty\tPayment\n'
        'Tech Store\tiPhone 14 128GB\t2\tPaid\n'
        'Tech Store\tSKU-004\t3\tPaid';

    final imported = parseImportedOrder(raw);
    final backend = MockBackend();
    final products = await backend.getProducts();
    final clients = await backend.getClients();

    expect(imported.clientName, 'Tech Store');
    expect(imported.paymentStatus, isNotNull);
    expect(findMatchingClient(clients, imported.clientName)?.name, 'Tech Store');
    expect(findMatchingProduct(products, imported.lines.first.lookup)?.id, 'p1');
    expect(findMatchingProduct(products, imported.lines.last.lookup)?.id, 'p4');
    expect(imported.lines.first.quantity, 2);
  });

  test('parses rows without headers as product and qty', () {
    const raw = 'Galaxy S24\t1\nAirPods Pro\t2';

    final imported = parseImportedOrder(raw);

    expect(imported.lines.length, 2);
    expect(imported.lines.first.lookup, 'Galaxy S24');
    expect(imported.lines.last.quantity, 2);
  });

  test('finds header after title rows', () {
    const raw = 'CRM отчет,,,,\n'
        'Обновлено: сегодня,,,,\n'
        'Товар,Количество,Клиент\n'
        'SKU-004,3,Tech Store\n'
        'Galaxy S24,1,Tech Store';

    final imported = parseImportedOrder(raw);

    expect(imported.lines.length, 2);
    expect(imported.lines.first.lookup, 'SKU-004');
    expect(imported.lines.first.quantity, 3);
  });

  test('builds csv urls for shared document links', () {
    final uris = googleSheetsCsvUris(
      'https://docs.google.com/spreadsheets/d/abc123/edit?gid=456#gid=456',
    );

    expect(uris, isNotEmpty);
    expect(uris.first.toString(), contains('/spreadsheets/d/abc123/export'));
    expect(uris.first.toString(), contains('gid=456'));
  });

  test('builds csv urls for links without scheme', () {
    final uris = googleSheetsCsvUris(
      'docs.google.com/spreadsheets/d/abc123/edit?gid=0',
    );

    expect(uris, isNotEmpty);
    expect(uris.first.toString(), contains('/spreadsheets/d/abc123/export'));
  });

  test('builds csv urls for published sheet links', () {
    final uris = googleSheetsCsvUris(
      'https://docs.google.com/spreadsheets/d/e/2PACX-abc/pubhtml?gid=0&single=true',
    );

    expect(uris, isNotEmpty);
    expect(uris.first.toString(), contains('/spreadsheets/d/e/2PACX-abc/pub'));
    expect(uris.first.toString(), contains('output=csv'));
  });

  test('parses google csv payload with bom and quoted commas', () {
    const raw = '\ufeffТовар,Количество,Клиент\n'
        '"iPhone 14, 128GB",2,Tech Store\n'
        'SKU-004,3,Tech Store';

    final imported = parseImportedOrder(raw);
    final first = imported.lines.first;

    expect(imported.lines.length, 2);
    expect(first.lookup, 'iPhone 14, 128GB');
    expect(first.quantity, 2);
    expect(imported.clientName, 'Tech Store');
  });

  test('normalizes google visualization json response', () {
    const body = 'google.visualization.Query.setResponse({'
        '"table":{"cols":[{"label":"Товар"},{"label":"Количество"}],'
        '"rows":[{"c":[{"v":"SKU-004"},{"v":3}]},{"c":[{"v":"Galaxy S24"},{"v":1}]}]}});';

    final normalized = normalizeImportedTablePayload(body);
    final imported = parseImportedOrder(normalized!);

    expect(imported.lines.length, 2);
    expect(imported.lines.first.lookup, 'SKU-004');
    expect(imported.lines.first.quantity, 3);
  });

  test('normalizes html table response', () {
    const body = '<html><body><table>'
        '<tr><th>Товар</th><th>Количество</th></tr>'
        '<tr><td>AirPods Pro</td><td>2</td></tr>'
        '</table></body></html>';

    final normalized = normalizeImportedTablePayload(body);
    final imported = parseImportedOrder(normalized!);

    expect(imported.lines.length, 1);
    expect(imported.lines.first.lookup, 'AirPods Pro');
    expect(imported.lines.first.quantity, 2);
  });

  test('throws clear message when no product and quantity columns', () {
    const raw = 'ID,Имя клиента,Компания\n'
        '1,Иван,ООО Технологии';

    expect(
      () => parseImportedOrder(raw),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Этот лист не подходит для импорта заказа'),
        ),
      ),
    );
  });

  test('parses xml order with item tags', () {
    const raw = '''
<order>
  <client>Tech Store</client>
  <paymentStatus>paid</paymentStatus>
  <items>
    <item><sku>SKU-004</sku><qty>3</qty></item>
    <item><productName>Galaxy S24</productName><quantity>1</quantity></item>
  </items>
</order>
''';

    final imported = parseImportedOrder(raw);

    expect(imported.clientName, 'Tech Store');
    expect(imported.paymentStatus, isNotNull);
    expect(imported.lines.length, 2);
    expect(imported.lines.first.lookup, 'SKU-004');
    expect(imported.lines.first.quantity, 3);
  });

  test('parses xml order with attributes', () {
    const raw = '''
<order>
  <item sku="SKU-004" qty="2" />
  <item product="AirPods Pro" quantity="4" />
</order>
''';

    final imported = parseImportedOrder(raw);

    expect(imported.lines.length, 2);
    expect(imported.lines.last.lookup, 'AirPods Pro');
    expect(imported.lines.last.quantity, 4);
  });

  test('parses xml from sample file', () {
    final raw = File('samples/order_import_simple.xml').readAsStringSync();
    final imported = parseImportedOrder(raw);

    expect(imported.clientName, 'Tech Store');
    expect(imported.lines.length, 2);
    expect(imported.lines.first.lookup, 'SKU-004');
    expect(imported.lines.first.quantity, 2);
  });
}
