import 'dart:io';
import 'package:crm/features/order_import.dart';
import 'package:dio/dio.dart';

Future<void> main(List<String> args) async {
  final link = args.isNotEmpty
      ? args.first
      : 'https://docs.google.com/spreadsheets/d/1zE9h3NiRfWHrkI7EY-HImJcrr7ZaHe9Tns6jw5-jHek/edit?usp=sharing';

  final urls = <Uri>[];
  final seen = <String>{};
  void addAll(Iterable<Uri> items) {
    for (final u in items) {
      if (seen.add(u.toString())) urls.add(u);
    }
  }

  addAll(googleSheetsCsvUris(link));

  final parsed = Uri.tryParse(link);
  String? docId;
  if (parsed != null) {
    final seg = parsed.pathSegments;
    final d = seg.indexOf('d');
    if (d >= 0 && d + 1 < seg.length) docId = seg[d + 1];
  }

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 20),
    followRedirects: true,
    maxRedirects: 6,
    responseType: ResponseType.plain,
    headers: const {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36',
      'Accept':
          'text/csv,text/tab-separated-values,text/plain,application/json,text/html;q=0.9,*/*;q=0.8',
    },
  ));

  if (docId != null && docId.isNotEmpty) {
    final htmlUri = Uri.https('docs.google.com', '/spreadsheets/d/$docId/htmlview');
    try {
      final htmlRes = await dio.getUri<String>(htmlUri,
          options: Options(validateStatus: (s) => s != null && s >= 200 && s < 400));
      final html = htmlRes.data ?? '';
      final gids = <String>{};
      for (final m in RegExp(r'gid=([0-9]+)').allMatches(html)) {
        final g = m.group(1);
        if (g != null && g.isNotEmpty) gids.add(g);
      }
      for (final gid in gids) {
        addAll(googleSheetsCsvUris('https://docs.google.com/spreadsheets/d/$docId/edit?gid=$gid'));
      }
      stdout.writeln('Found gids: ${gids.join(', ')}');
    } catch (e) {
      stdout.writeln('Could not discover gids: $e');
    }
  }

  stdout.writeln('Trying ${urls.length} url variants');

  var successCount = 0;
  for (final url in urls) {
    try {
      final res = await dio.getUri<String>(url,
          options: Options(validateStatus: (s) => s != null && s >= 200 && s < 500));
      final status = res.statusCode;
      final body = (res.data ?? '').trim();
      if (body.isEmpty) {
        stdout.writeln('[${status}] EMPTY $url');
        continue;
      }

      final normalized = normalizeImportedTablePayload(body)?.trim();
      if (normalized == null || normalized.isEmpty) {
        stdout.writeln('[${status}] NOT_NORMALIZED $url');
        continue;
      }

      try {
        final parsedOrder = parseImportedOrder(normalized);
        successCount++;
        final first = parsedOrder.lines.isNotEmpty
            ? '${parsedOrder.lines.first.lookup} x${parsedOrder.lines.first.quantity}'
            : '-';
        stdout.writeln('[${status}] OK lines=${parsedOrder.lines.length} first=$first :: $url');
      } on FormatException catch (e) {
        stdout.writeln('[${status}] PARSE_FAIL ${e.message} :: $url');
      }
    } catch (e) {
      stdout.writeln('[ERR] $url -> $e');
    }
  }

  stdout.writeln('SUCCESS_VARIANTS=$successCount');
}
