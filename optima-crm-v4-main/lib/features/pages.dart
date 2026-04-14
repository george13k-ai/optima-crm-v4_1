import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:crm/domain/entities/entities.dart';
import 'package:crm/features/cubits.dart';
import 'package:crm/features/order_import.dart';
import 'package:crm/features/qwen_xml_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

// ── Document export ────────────────────────────────────────────────────────

enum _DocType { invoice, bill, act }

extension _DocTypeLabel on _DocType {
  String get label => switch (this) {
        _DocType.invoice => 'Накладная',
        _DocType.bill => 'Счёт',
        _DocType.act => 'Акт',
      };
  String get header => switch (this) {
        _DocType.invoice => 'ТОВАРНАЯ НАКЛАДНАЯ',
        _DocType.bill => 'СЧЁТ НА ОПЛАТУ',
        _DocType.act => 'АКТ ВЫПОЛНЕННЫХ РАБОТ',
      };
}

String _buildDocumentText(Order order, _DocType type) {
  final fmt = NumberFormat('#,##0', 'ru_RU');
  String rub(double v) => '${fmt.format(v.round())} ₽';
  final dateStr = DateFormat('dd.MM.yyyy').format(order.date);
  final line = '─' * 48;
  final dline = '═' * 48;

  final sb = StringBuffer();
  sb.writeln(dline);
  sb.writeln('  ${type.header} № ${order.orderNumber}');
  sb.writeln(dline);
  sb.writeln('Дата:       $dateStr');
  sb.writeln('Поставщик:  Оптима CRM');
  sb.writeln('Покупатель: ${order.clientName}');
  if (order.comment != null && order.comment!.isNotEmpty) {
    sb.writeln('Примечание: ${order.comment}');
  }
  sb.writeln(line);
  sb.writeln(' №  Наименование              Кол    Цена       Сумма');
  sb.writeln(line);

  for (var i = 0; i < order.items.length; i++) {
    final item = order.items[i];
    final n = '${i + 1}'.padLeft(2);
    final name = item.productName.length > 24
        ? '${item.productName.substring(0, 22)}..'
        : item.productName.padRight(24);
    final qty = '${item.quantity} шт'.padLeft(5);
    final price = rub(item.salePrice).padLeft(10);
    final total = rub(item.lineTotal).padLeft(10);
    sb.writeln('$n  $name$qty$price$total');
  }

  sb.writeln(line);
  sb.writeln(
    'Позиций: ${order.items.length}   '
    'Кол-во: ${order.totalQuantity} шт',
  );
  sb.writeln('');
  sb.writeln('  ИТОГО к оплате:  ${rub(order.totalAmount)}');
  if (type != _DocType.bill) {
    sb.writeln('  Себестоимость:   ${rub(order.totalCost)}');
    sb.writeln('  Прибыль:         ${rub(order.profit)}');
  }
  sb.writeln(dline);
  sb.writeln(
    'Статус оплаты: ${order.paymentStatus == PaymentStatus.paid ? "Оплачено ✓" : "Ожидает оплаты"}',
  );
  sb.writeln(dline);
  return sb.toString();
}

String money(num v) => NumberFormat.currency(
  locale: 'ru_RU',
  symbol: '₽',
  decimalDigits: 0,
).format(v);

String date(DateTime v) => DateFormat('dd.MM.yyyy HH:mm').format(v);
String pStatus(PaymentStatus p) =>
    p == PaymentStatus.paid ? 'Оплачено' : 'Ожидает оплаты';
String stockStatus(Product p) => switch (p.status) {
  ProductAvailabilityStatus.inStock => 'В наличии',
  ProductAvailabilityStatus.lowStock => 'Мало на складе',
  ProductAvailabilityStatus.outOfStock => 'Нет в наличии',
  ProductAvailabilityStatus.newProduct => 'Новинка',
};

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _Background(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _Panel(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Logo(size: 76),
                      const SizedBox(height: 20),
                      Text(
                        'Оптима CRM',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'CRM для заказов, клиентов и склада. Быстро собирайте заказы, импортируйте таблицы и держите остатки под контролем.',
                        style: TextStyle(color: Colors.white70, height: 1.5),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: const [
                          _MiniBadge(
                            icon: Icons.table_chart_outlined,
                            label: 'Импорт Google Sheets',
                          ),
                          _MiniBadge(
                            icon: Icons.inventory_2_outlined,
                            label: 'Остатки и SKU',
                          ),
                          _MiniBadge(
                            icon: Icons.receipt_long_outlined,
                            label: 'Заказы и прибыль',
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => context.go('/dashboard'),
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: const Text('Открыть рабочее пространство'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ShellScaffold extends StatelessWidget {
  const ShellScaffold({super.key, required this.child, required this.index});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    return _Background(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(child: child),
        extendBody: true,
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: const Color(0xFF0F1823).withValues(alpha: 0.9),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: NavigationBarTheme(
                  data: NavigationBarThemeData(
                    labelTextStyle: WidgetStateProperty.resolveWith(
                      (states) => TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: states.contains(WidgetState.selected)
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: states.contains(WidgetState.selected)
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  child: NavigationBar(
                    height: 68,
                    backgroundColor: Colors.transparent,
                    selectedIndex: index,
                    onDestinationSelected: (i) => context.go(
                      [
                        '/dashboard',
                        '/products',
                        '/orders',
                        '/clients',
                        '/stock',
                      ][i],
                    ),
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.space_dashboard_outlined),
                        label: 'Главная',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.inventory_2_outlined),
                        label: 'Товары',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.receipt_long_outlined),
                        label: 'Заказы',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.people_outline),
                        label: 'Клиенты',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.warehouse_outlined),
                        label: 'Склад',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardCubit, DashboardStats?>(
      builder: (_, stats) {
        if (stats == null) {
          return const _PageShell(
            title: 'Панель управления',
            subtitle: 'Ключевые показатели продаж, оплаты и остатков.',
            child: Center(child: CircularProgressIndicator()),
          );
        }

        return _PageShell(
          title: 'Панель управления',
          subtitle: 'Ключевые показатели продаж, оплаты и остатков.',
          child: ListView(
            padding: const EdgeInsets.only(bottom: 124),
            children: [
              _HeroSummary(stats: stats),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _StatCard(
                    title: 'Заказы',
                    value: '${stats.ordersCount}',
                    hint: 'Всего создано',
                    icon: Icons.receipt_long_outlined,
                  ),
                  _StatCard(
                    title: 'Выручка',
                    value: money(stats.totalSales),
                    hint: 'Сумма продаж',
                    icon: Icons.currency_ruble_rounded,
                  ),
                  _StatCard(
                    title: 'Не оплачено',
                    value: '${stats.unpaidOrdersCount}',
                    hint: 'Требует контроля',
                    icon: Icons.pending_actions_outlined,
                  ),
                  _StatCard(
                    title: 'Низкий остаток',
                    value: '${stats.lowStockCount}',
                    hint: 'Нужна закупка',
                    icon: Icons.warning_amber_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle(
                      title: 'Быстрые действия',
                      subtitle:
                          'Частые сценарии, чтобы не переключаться между экранами вручную.',
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _QuickActionButton(
                          icon: Icons.add_shopping_cart_rounded,
                          label: 'Создать заказ',
                          onTap: () => context.push('/create-order'),
                        ),
                        _QuickActionButton(
                          icon: Icons.inventory_2_outlined,
                          label: 'Открыть товары',
                          onTap: () => context.go('/products'),
                        ),
                        _QuickActionButton(
                          icon: Icons.receipt_long_outlined,
                          label: 'История заказов',
                          onTap: () => context.go('/orders'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ProductsPage extends StatelessWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProductsCubit, ProductsState>(
      builder: (context, s) => _PageShell(
        title: 'Товары',
        subtitle: 'Поиск, фильтры и добавление товаров в текущий заказ.',
        action: IconButton(
          onPressed: () => context.push('/create-order'),
          icon: const Icon(Icons.shopping_cart_outlined),
          tooltip: 'Открыть заказ',
        ),
        child: Column(
          children: [
            _Panel(
              child: Column(
                children: [
                  TextField(
                    onChanged: context.read<ProductsCubit>().setSearch,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Поиск по названию или SKU',
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final vertical = constraints.maxWidth < 560;
                      final categories = s.items
                          .map((e) => e.category)
                          .toSet()
                          .toList(growable: false);
                      final brands = s.items
                          .map((e) => e.brand)
                          .toSet()
                          .toList(growable: false);
                      // key forces widget recreation when the selected value
                      // changes externally (e.g. filter cleared from cubit),
                      // so initialValue is re-applied on every state change.
                      final categoryField = DropdownButtonFormField<String>(
                        key: ValueKey('cat-${s.category}'),
                        initialValue:
                            categories.contains(s.category) ? s.category : null,
                        hint: const Text('Категория'),
                        items: categories
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(growable: false),
                        onChanged: context.read<ProductsCubit>().setCategory,
                      );
                      final brandField = DropdownButtonFormField<String>(
                        key: ValueKey('brand-${s.brand}'),
                        initialValue:
                            brands.contains(s.brand) ? s.brand : null,
                        hint: const Text('Бренд'),
                        items: brands
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(growable: false),
                        onChanged: context.read<ProductsCubit>().setBrand,
                      );
                      if (vertical) {
                        return Column(
                          children: [
                            categoryField,
                            const SizedBox(height: 12),
                            brandField,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: categoryField),
                          const SizedBox(width: 12),
                          Expanded(child: brandField),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: s.filtered.isEmpty
                  ? const _EmptyPanel(
                      icon: Icons.search_off_rounded,
                      title: 'Ничего не найдено',
                      subtitle:
                          'Измените фильтры или попробуйте другой поисковый запрос.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 124),
                      itemCount: s.filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) =>
                          _ProductTile(product: s.filtered[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class CreateOrderPage extends StatelessWidget {
  const CreateOrderPage({super.key});
  static const MethodChannel _importPickerChannel = MethodChannel(
    'crm/import_picker',
  );

  @override
  Widget build(BuildContext context) {
    return _Background(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Новый заказ')),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: BlocConsumer<OrderDraftCubit, OrderDraftState>(
              listener: (context, s) {
                if (s.createdOrder != null) {
                  final createdOrder = s.createdOrder!;
                  context.read<OrderDraftCubit>().clearCreated();
                  context.read<OrdersCubit>().load();
                  context.read<ProductsCubit>().load();
                  context.read<StockCubit>().load();
                  context.read<DashboardCubit>().load();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Заказ ${createdOrder.orderNumber} успешно создан.',
                      ),
                    ),
                  );
                  context.go('/orders');
                }
                if (s.error != null) {
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Ошибка'),
                      content: Text(
                        s.error!,
                        style: const TextStyle(height: 1.5),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('ОК'),
                        ),
                      ],
                    ),
                  );
                }
              },
              builder: (context, s) => Column(
                children: [
                  Expanded(
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: _Panel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _SectionTitle(
                                  title: 'Импорт заказа',
                                  subtitle:
                                      'Импортируйте публичную Google Sheets ссылку, XML/XLSX файл или вставьте строки таблицы.',
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    FilledButton.tonalIcon(
                                      onPressed: () =>
                                          _showImportDialog(context),
                                      icon: const Icon(
                                        Icons.content_paste_go_rounded,
                                      ),
                                      label:
                                          const Text('Импорт ссылки / файла'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          context.go('/products'),
                                      icon: const Icon(
                                        Icons.inventory_2_outlined,
                                      ),
                                      label:
                                          const Text('Добавить товары вручную'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 12)),
                        SliverToBoxAdapter(
                          child: _Panel(
                            child: Column(
                              children: [
                                BlocBuilder<ClientsCubit, List<Client>>(
                                  builder: (_, clients) =>
                                      DropdownButtonFormField<String>(
                                        initialValue: s.client?.id,
                                        hint: const Text('Клиент'),
                                        items: clients
                                            .map(
                                              (c) => DropdownMenuItem(
                                                value: c.id,
                                                child: Text(c.name),
                                              ),
                                            )
                                            .toList(growable: false),
                                        onChanged: (id) => context
                                            .read<OrderDraftCubit>()
                                            .pickClient(
                                              clients
                                                  .where((c) => c.id == id)
                                                  .firstOrNull,
                                            ),
                                      ),
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<PaymentStatus>(
                                  initialValue: s.paymentStatus,
                                  items: PaymentStatus.values
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e,
                                          child: Text(pStatus(e)),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (v) => context
                                      .read<OrderDraftCubit>()
                                      .setPayment(v ?? PaymentStatus.unpaid),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  key: ValueKey('comment-${s.comment}'),
                                  initialValue: s.comment,
                                  onChanged: context
                                      .read<OrderDraftCubit>()
                                      .setComment,
                                  minLines: 2,
                                  maxLines: 4,
                                  decoration: const InputDecoration(
                                    labelText: 'Комментарий к заказу',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 12)),
                        if (s.lines.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: _EmptyPanel(
                              icon: Icons.shopping_cart_outlined,
                              title: 'Черновик пока пуст',
                              subtitle:
                                  'Добавьте товары вручную или импортируйте Google Sheets/XML/таблицу.',
                            ),
                          )
                        else
                          SliverList.separated(
                            itemCount: s.lines.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, i) =>
                                _DraftLineTile(line: s.lines[i]),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Panel(
                    child: Column(
                      children: [
                        _summaryRow('Позиции', '${s.itemsCount}'),
                        _summaryRow('Количество', '${s.totalQuantity}'),
                        _summaryRow('Сумма', money(s.totalAmount)),
                        _summaryRow('Себестоимость', money(s.totalCost)),
                        _summaryRow('Прибыль', money(s.profit)),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () =>
                                context.read<OrderDraftCubit>().createOrder(),
                            child: const Text('Подтвердить заказ'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showImportDialog(BuildContext context) async {
    final controller = TextEditingController();
    final imported = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Импорт заказа'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Вставьте ссылку на Google Sheets, строки таблицы или выберите файл XML/XLS/XLSX. Таблица должна быть открыта для просмотра всем.',
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 10,
                maxLines: 16,
                decoration: const InputDecoration(
                  hintText:
                      'https://docs.google.com/spreadsheets/d/... или строки с колонками Товар / SKU / Количество',
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop('__pick_import_file__'),
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Файл XML/XLS/XLSX'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Импортировать'),
          ),
        ],
      ),
    );

    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    var importInput = imported;
    if (importInput == '__pick_import_file__') {
      try {
        importInput = await _pickImportFilePayload();
      } on FormatException catch (e) {
        if (!context.mounted) return;
        await _showImportError(context, e.message);
        return;
      }
    }

    if (importInput == null || importInput.trim().isEmpty) return;

    final products = context.read<ProductsCubit>().state.items;
    final clients = context.read<ClientsCubit>().state;
    final draftCubit = context.read<OrderDraftCubit>();

    try {
      var importPayload = importInput.trim();

      // If user pasted a Google Sheets URL, fetch the data first
      final sheetUrls = await _buildGoogleSheetCandidateUrls(importPayload);
      if (sheetUrls.isNotEmpty) {
        final fetched = await _fetchGoogleSheetPayload(sheetUrls);
        if (fetched != null && fetched.trim().isNotEmpty) {
          importPayload = fetched.trim();
        } else {
          throw const FormatException(
            'Не удалось загрузить данные из Google Sheets.\n\n'
            'Убедитесь, что таблица открыта для просмотра всем:\n'
            'Файл → Настройки доступа → Все, у кого есть ссылка → Читатель.',
          );
        }
      }

      if (_looksLikeXmlPayload(importPayload) ||
          _looksLikeTabularPayload(importPayload)) {
        final qwenNormalized = await QwenXmlService.instance
            .tryNormalizePayload(importPayload);
        if (qwenNormalized != null && qwenNormalized.trim().isNotEmpty) {
          importPayload = qwenNormalized.trim();
        }
      }

      final message = draftCubit.importTableText(
        raw: importPayload,
        products: products,
        clients: clients,
      );
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
        ),
      );
    } on FormatException catch (e) {
      if (!context.mounted) return;
      await _showImportError(context, e.message);
    }
  }

  Future<void> _showImportError(BuildContext context, String message) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ошибка импорта'),
        content: Text(message, style: const TextStyle(height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('ОК'),
          ),
        ],
      ),
    );
  }

  Future<String> _pickImportFilePayload() async {
    if (!Platform.isAndroid) {
      throw const FormatException(
        'Выбор файла сейчас поддерживается только на Android.',
      );
    }

    final raw = await _importPickerChannel.invokeMethod<dynamic>(
      'pickImportFile',
    );
    if (raw == null || raw is! Map) {
      throw const FormatException('Выбор файла отменён.');
    }

    final fileName = (raw['fileName'] ?? '').toString().trim();
    final bytesBase64 = (raw['bytesBase64'] ?? '').toString().trim();
    if (bytesBase64.isEmpty) {
      throw const FormatException('Файл пустой или не читается.');
    }

    Uint8List bytes;
    try {
      bytes = base64Decode(bytesBase64);
    } catch (_) {
      throw const FormatException('Не удалось декодировать содержимое файла.');
    }
    if (bytes.isEmpty) {
      throw const FormatException('Файл пустой.');
    }

    final ext = _fileExtension(fileName);
    if (ext == 'xml') {
      final decoded = utf8.decode(bytes, allowMalformed: true).trim();
      if (decoded.isEmpty) {
        throw const FormatException('XML файл пустой.');
      }
      if (!_looksLikeXmlPayload(decoded)) {
        throw const FormatException('Выбранный файл не похож на XML.');
      }
      return decoded;
    }

    if (ext == 'xlsx' || ext == 'xls') {
      final tableText = _decodeSpreadsheetToTable(bytes);
      if (tableText == null || tableText.trim().isEmpty) {
        if (ext == 'xls') {
          final normalized = await QwenXmlService.instance
              .tryNormalizeBinarySpreadsheet(fileName: fileName, bytes: bytes);
          if (normalized != null && normalized.trim().isNotEmpty) {
            return normalized;
          }
        }
        throw const FormatException(
          'Не удалось прочитать таблицу из Excel файла.',
        );
      }
      return tableText;
    }

    final plainText = utf8.decode(bytes, allowMalformed: true).trim();
    if (plainText.isNotEmpty) return plainText;
    throw const FormatException('Поддерживаются файлы XML, XLSX и XLS.');
  }

  bool _looksLikeXmlPayload(String value) {
    final trimmed = value.trimLeft().toLowerCase();
    return trimmed.startsWith('<') || trimmed.startsWith('<?xml');
  }

  bool _looksLikeTabularPayload(String value) {
    return value.contains('\t') || value.contains(',') || value.contains(';');
  }

  String _fileExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot + 1 >= fileName.length) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  String? _decodeSpreadsheetToTable(Uint8List bytes) {
    try {
      final decoder = SpreadsheetDecoder.decodeBytes(bytes);
      if (decoder.tables.isEmpty) return null;
      final firstTable = decoder.tables.values.first;
      final rows = <String>[];
      for (final row in firstTable.rows) {
        final cells = row
            .map((cell) => (cell ?? '').toString().replaceAll('\n', ' ').trim())
            .toList(growable: false);
        if (cells.every((cell) => cell.isEmpty)) continue;
        rows.add(cells.join('\t'));
      }
      return rows.isEmpty ? null : rows.join('\n');
    } catch (_) {
      return null;
    }
  }

  Future<String?> _fetchGoogleSheetPayload(List<Uri> urls) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 18),
        followRedirects: true,
        maxRedirects: 6,
        responseType: ResponseType.plain,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36',
          'Accept':
              'text/csv,text/tab-separated-values,text/plain,application/json,text/html;q=0.9,*/*;q=0.8',
        },
      ),
    );

    for (final url in urls) {
      try {
        final response = await dio.getUri<String>(
          url,
          options: Options(
            // Accept only successful responses; 4xx without redirect means
            // access denied — DioException is caught below and we try next URL
            validateStatus: (status) =>
                status != null && status >= 200 && status < 300,
          ),
        );
        final body = response.data?.trim();
        if (body == null || body.isEmpty) continue;
        if (_looksLikeGoogleSignInPage(body)) continue;

        final normalized = normalizeImportedTablePayload(body);
        if (normalized != null && normalized.trim().isNotEmpty) {
          final candidate = normalized.trim();
          try {
            final parsed = parseImportedOrder(candidate);
            if (parsed.lines.isNotEmpty) {
              return candidate;
            }
          } on FormatException {
            continue;
          }
        }
      } on DioException {
        continue;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<List<Uri>> _buildGoogleSheetCandidateUrls(String input) async {
    final urls = <Uri>[];
    final seen = <String>{};

    void addAll(Iterable<Uri> items) {
      for (final item in items) {
        if (seen.add(item.toString())) {
          urls.add(item);
        }
      }
    }

    addAll(googleSheetsCsvUris(input));

    final parsed = _parseGoogleLikeUri(input);
    if (parsed == null) return urls;
    if (!_isGoogleSheetHost(parsed.host)) return urls;

    final docId = _extractGoogleSheetDocId(parsed);
    if (docId.isEmpty) return urls;

    addAll(
      googleSheetsCsvUris('https://docs.google.com/spreadsheets/d/$docId/edit'),
    );

    final gid = _extractGidFromUri(parsed);
    if (gid != null && gid.isNotEmpty) {
      // GID already known — add it and skip the extra discovery request
      addAll(
        googleSheetsCsvUris(
          'https://docs.google.com/spreadsheets/d/$docId/edit?gid=$gid',
        ),
      );
    } else {
      // No GID in URL — try to discover sheet tabs from the HTML view
      final discoveredGids = await _discoverGoogleSheetGids(docId);
      for (final discoveredGid in discoveredGids) {
        addAll(
          googleSheetsCsvUris(
            'https://docs.google.com/spreadsheets/d/$docId/edit?gid=$discoveredGid',
          ),
        );
      }
    }

    return urls;
  }

  Future<List<String>> _discoverGoogleSheetGids(String docId) async {
    final htmlUri = Uri.https(
      'docs.google.com',
      '/spreadsheets/d/$docId/htmlview',
    );

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 10),
          responseType: ResponseType.plain,
          followRedirects: true,
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36',
            'Accept': 'text/html,*/*;q=0.8',
          },
        ),
      );
      final response = await dio.getUri<String>(
        htmlUri,
        options: Options(
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      final html = response.data;
      if (html == null || html.isEmpty) return const [];
      if (_looksLikeGoogleSignInPage(html)) return const [];

      final gids = <String>{};
      for (final match in RegExp(r'gid=([0-9]+)').allMatches(html)) {
        final gid = match.group(1);
        if (gid != null && gid.isNotEmpty) gids.add(gid);
      }
      return gids.toList(growable: false);
    } catch (_) {
      return const [];
    }
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

  bool _isGoogleSheetHost(String host) {
    final normalized = host.toLowerCase();
    return normalized.contains('docs.google.com') ||
        normalized.contains('drive.google.com');
  }

  String _extractGoogleSheetDocId(Uri uri) {
    final segments = uri.pathSegments;
    final docIndex = segments.indexOf('d');
    if (docIndex >= 0 && docIndex + 1 < segments.length) {
      return segments[docIndex + 1];
    }
    return uri.queryParameters['id'] ?? '';
  }

  String? _extractGidFromUri(Uri uri) {
    final queryGid = uri.queryParameters['gid'];
    if (queryGid != null && queryGid.isNotEmpty) return queryGid;

    final fragment = uri.fragment;
    if (fragment.contains('gid=')) {
      final gid = fragment.split('gid=').last.split('&').first;
      if (gid.isNotEmpty) return gid;
    }
    return null;
  }

  bool _looksLikeGoogleSignInPage(String body) {
    final lower = body.toLowerCase();
    // Google redirects to sign-in or shows error pages in several forms
    if (lower.contains('accounts.google.com')) return true;
    if (lower.contains('servicelogin')) return true;
    if (lower.contains('myaccount.google.com')) return true;
    if (lower.contains('gaia_loginform')) return true;
    if (lower.contains('signin/v2')) return true;
    // "Access denied" error pages from Google
    if (lower.contains('access denied') || lower.contains('access_denied')) {
      return true;
    }
    // Generic sign-in page check — must have both "sign in" and "google"
    if (lower.contains('sign in') && lower.contains('google')) return true;
    // Short response with no data characters is likely an error page
    if (body.length < 64 && !body.contains('\t') && !body.contains(',')) {
      return true;
    }
    return false;
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OrdersCubit, List<Order>>(
      builder: (_, orders) => _PageShell(
        title: 'Заказы',
        subtitle: 'История заказов, сумма продаж и маржинальность.',
        action: IconButton(
          onPressed: () => context.push('/create-order'),
          icon: const Icon(Icons.add_shopping_cart_rounded),
        ),
        child: orders.isEmpty
            ? const _EmptyPanel(
                icon: Icons.receipt_long_outlined,
                title: 'Заказов пока нет',
                subtitle:
                    'Создайте первый заказ вручную или импортируйте таблицу.',
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 124),
                itemCount: orders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _OrderTile(order: orders[i]),
              ),
      ),
    );
  }
}

class OrderDetailsPage extends StatelessWidget {
  const OrderDetailsPage({super.key, required this.id});

  final String id;

  void _showExportSheet(BuildContext context, Order order) {
    var selectedType = _DocType.invoice;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121A24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final text = _buildDocumentText(order, selectedType);
          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scrollCtrl) => Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                // Type selector
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: _DocType.values.map((t) {
                      final selected = t == selectedType;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: GestureDetector(
                            onTap: () => setState(() => selectedType = t),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: selected
                                    ? const Color(0xFFF18B54)
                                    : Colors.white.withValues(alpha: 0.07),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                t.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: selected
                                      ? const Color(0xFF10151D)
                                      : Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                // Document preview
                Expanded(
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.07),
                          ),
                        ),
                        child: SelectableText(
                          text,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.55,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Copy button
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: text));
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Документ скопирован в буфер обмена'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Копировать'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = context.select(
      (OrdersCubit c) => c.state.where((o) => o.id == id).firstOrNull,
    );
    return _Background(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(order?.orderNumber ?? 'Заказ'),
          actions: [
            if (order != null) ...[
              IconButton(
                icon: const Icon(Icons.receipt_outlined),
                tooltip: 'Экспорт документа',
                onPressed: () => _showExportSheet(context, order),
              ),
            ],
            if (order != null)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Удалить заказ',
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Удалить заказ?'),
                      content: Text(
                        'Заказ ${order.orderNumber} будет удалён без возможности восстановления.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Отмена'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text(
                            'Удалить',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && context.mounted) {
                    final ordersCubit = context.read<OrdersCubit>();
                    final dashCubit = context.read<DashboardCubit>();
                    await ordersCubit.delete(order.id);
                    await dashCubit.load();
                    if (context.mounted) context.go('/orders');
                  }
                },
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: order == null
                ? const _EmptyPanel(
                    icon: Icons.inbox_outlined,
                    title: 'Заказ не найден',
                    subtitle: 'Вернитесь к списку и откройте другой заказ.',
                  )
                // ListView.builder renders only visible items — essential for
                // orders with hundreds of lines (avoids building all at once).
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: order.items.length + 1,
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        // Header: order summary panel
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _Panel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  order.clientName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  date(order.date),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _MiniBadge(
                                      icon: Icons.payments_outlined,
                                      label: pStatus(order.paymentStatus),
                                    ),
                                    _MiniBadge(
                                      icon: Icons.currency_ruble_rounded,
                                      label:
                                          'Сумма ${money(order.totalAmount)}',
                                    ),
                                    _MiniBadge(
                                      icon: Icons.trending_up_rounded,
                                      label:
                                          'Прибыль ${money(order.profit)}',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      // Item rows — built lazily
                      final item = order.items[i - 1];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _Panel(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.productName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${item.quantity} шт. x ${money(item.salePrice)}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                money(item.lineTotal),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class ClientsPage extends StatelessWidget {
  const ClientsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ClientsCubit, List<Client>>(
      builder: (_, clients) => _PageShell(
        title: 'Клиенты',
        subtitle: 'Контактная база и компании, с которыми вы работаете.',
        child: ListView.separated(
          padding: const EdgeInsets.only(bottom: 124),
          itemCount: clients.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _Panel(
            child: Row(
              children: [
                _Avatar(
                  initial: clients[i].name.isEmpty ? 'К' : clients[i].name[0],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clients[i].name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        clients[i].phone,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StockPage extends StatelessWidget {
  const StockPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StockCubit, List<Product>>(
      builder: (_, products) => _PageShell(
        title: 'Склад',
        subtitle: 'Текущие остатки, минимальные пороги и риск дефицита.',
        child: ListView.separated(
          padding: const EdgeInsets.only(bottom: 124),
          itemCount: products.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _Panel(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        products[i].name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Остаток ${products[i].stock} / минимум ${products[i].minStock}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                _MiniBadge(
                  icon: Icons.warehouse_outlined,
                  label: stockStatus(products[i]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageShell extends StatelessWidget {
  const _PageShell({
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Logo(size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              if (action != null) ...[action!],
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _HeroSummary extends StatelessWidget {
  const _HeroSummary({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            title: 'Сегодня в работе',
            subtitle:
                'Оперативный блок с главным фокусом по продажам и остаткам.',
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final vertical = constraints.maxWidth < 560;
              final salesCard = Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFF18B54).withValues(alpha: 0.28),
                      const Color(0xFFB6456A).withValues(alpha: 0.18),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Выручка за период',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      money(stats.totalSales),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Неоплаченных заказов: ${stats.unpaidOrdersCount}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              );
              final sideCards = Column(
                children: [
                  _CompactInfo(
                    title: 'Низкий остаток',
                    value: '${stats.lowStockCount}',
                  ),
                  const SizedBox(height: 10),
                  _CompactInfo(
                    title: 'Всего заказов',
                    value: '${stats.ordersCount}',
                  ),
                ],
              );
              if (vertical) {
                return Column(
                  children: [salesCard, const SizedBox(height: 12), sideCards],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: salesCard),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: sideCards),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final vertical = constraints.maxWidth < 560;
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniBadge(icon: Icons.sell_outlined, label: product.brand),
                  _MiniBadge(
                    icon: Icons.tag_outlined,
                    label: product.sku ?? 'Без SKU',
                  ),
                  _MiniBadge(
                    icon: Icons.inventory_2_outlined,
                    label: stockStatus(product),
                  ),
                ],
              ),
            ],
          );
          final aside = Column(
            crossAxisAlignment: vertical
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              Text(
                money(product.salePrice),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'В наличии: ${product.stock}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 10),
              FilledButton.tonal(
                onPressed: product.stock <= 0
                    ? null
                    : () => context.read<OrderDraftCubit>().addProduct(product),
                child: const Text('Добавить'),
              ),
            ],
          );
          if (vertical) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [info, const SizedBox(height: 14), aside],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 14),
              aside,
            ],
          );
        },
      ),
    );
  }
}

class _DraftLineTile extends StatelessWidget {
  const _DraftLineTile({required this.line});

  final DraftLine line;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final vertical = constraints.maxWidth < 560;
          final lineTotal = line.quantity * line.product.salePrice;
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.product.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${line.quantity} шт. × ${money(line.product.salePrice)} = ${money(lineTotal)}',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          );
          final controls = Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              IconButton(
                onPressed: () => context.read<OrderDraftCubit>().setQty(
                  line.product.id,
                  line.quantity - 1,
                ),
                icon: const Icon(Icons.remove_rounded),
              ),
              Text(
                '${line.quantity}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              IconButton(
                onPressed: () => context.read<OrderDraftCubit>().setQty(
                  line.product.id,
                  line.quantity + 1,
                ),
                icon: const Icon(Icons.add_rounded),
              ),
              IconButton(
                onPressed: () =>
                    context.read<OrderDraftCubit>().remove(line.product.id),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          );
          if (vertical) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [info, const SizedBox(height: 12), controls],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              controls,
            ],
          );
        },
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => context.push('/order/${order.id}'),
      child: _Panel(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final vertical = constraints.maxWidth < 560;
            final mainInfo = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.orderNumber,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(order.clientName),
                const SizedBox(height: 4),
                Text(
                  '${date(order.date)} • ${pStatus(order.paymentStatus)}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            );
            final moneyInfo = Column(
              crossAxisAlignment: vertical
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                Text(
                  money(order.totalAmount),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Прибыль ${money(order.profit)}',
                  style: const TextStyle(color: Color(0xFF7ED9A4)),
                ),
              ],
            );
            if (vertical) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [mainInfo, const SizedBox(height: 14), moneyInfo],
              );
            }
            return Row(
              children: [
                Expanded(child: mainInfo),
                const SizedBox(width: 12),
                moneyInfo,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
      ],
    );
  }
}

class _CompactInfo extends StatelessWidget {
  const _CompactInfo({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Colors.white.withValues(alpha: 0.05),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [
                const Color(0xFF162131).withValues(alpha: 0.9),
                const Color(0xFF101822).withValues(alpha: 0.82),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFF18B54).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, size: 30),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white70, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.hint,
    required this.icon,
  });

  final String title;
  final String value;
  final String hint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
            const SizedBox(height: 6),
            Text(hint, style: const TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(fontSize: 12, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFFF18B54), Color(0xFFE15E63)],
        ),
      ),
      child: Text(
        initial.toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _Background extends StatelessWidget {
  const _Background({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF09111A), Color(0xFF0C1420), Color(0xFF0A1018)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            top: -70,
            right: -40,
            child: _Glow(color: Color(0xFFF18B54), size: 220),
          ),
          const Positioned(
            top: 160,
            left: -30,
            child: _Glow(color: Color(0xFF6EC6CA), size: 180),
          ),
          const Positioned(
            bottom: -30,
            right: 30,
            child: _Glow(color: Color(0xFF5C7CFA), size: 190),
          ),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.26),
              color.withValues(alpha: 0.05),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          colors: [Color(0xFFF18B54), Color(0xFFE25E62)],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.14),
        child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
      ),
    );
  }
}
