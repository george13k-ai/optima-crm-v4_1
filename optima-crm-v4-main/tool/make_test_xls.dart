import 'dart:io';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

void main() {
  final template = File(r'C:\Users\Kirik\AppData\Local\Pub\Cache\hosted\pub.dev\spreadsheet_decoder-2.3.0\test\files\default.xlsx');
  final bytes = template.readAsBytesSync();
  final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: true);
  final sheet = decoder.tables.keys.first;

  for (var i = 0; i < 4; i++) {
    decoder.insertColumn(sheet, i);
  }
  for (var i = 0; i < 3; i++) {
    decoder.insertRow(sheet, i);
  }

  decoder.updateCell(sheet, 0, 0, 'Client');
  decoder.updateCell(sheet, 1, 0, 'Payment');
  decoder.updateCell(sheet, 2, 0, 'Product');
  decoder.updateCell(sheet, 3, 0, 'Qty');

  decoder.updateCell(sheet, 0, 1, 'Tech Store');
  decoder.updateCell(sheet, 1, 1, 'Paid');
  decoder.updateCell(sheet, 2, 1, 'SKU-004');
  decoder.updateCell(sheet, 3, 1, 2);

  decoder.updateCell(sheet, 0, 2, 'Tech Store');
  decoder.updateCell(sheet, 1, 2, 'Paid');
  decoder.updateCell(sheet, 2, 2, 'Galaxy S24');
  decoder.updateCell(sheet, 3, 2, 1);

  final outDir = Directory(r'c:\appps\optima crm v4\optima-crm-v4-main\samples');
  outDir.createSync(recursive: true);

  final xlsx = File('${outDir.path}\\order_import_test.xlsx');
  xlsx.writeAsBytesSync(decoder.encode());

  final xls = File('${outDir.path}\\order_import_test.xls');
  xls.writeAsBytesSync(xlsx.readAsBytesSync());

  print(xlsx.path);
  print(xls.path);
}
