import 'dart:io';
import 'dart:ui';

import 'package:crm/domain/entities/entities.dart';
import 'package:crm/features/cubits.dart';
import 'package:crm/features/google_sheets_auth.dart';
import 'package:crm/features/order_import.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
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
                          _MiniBadge(icon: Icons.table_chart_outlined, label: 'Импорт из Google Sheets'),
                          _MiniBadge(icon: Icons.inventory_2_outlined, label: 'Остатки и SKU'),
                          _MiniBadge(icon: Icons.receipt_long_outlined, label: 'Заказы и прибыль'),
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: NavigationBar(
                height: 76,
                backgroundColor: const Color(0xFF0F1823).withValues(alpha: 0.9),
                selectedIndex: index,
                onDestinationSelected: (i) => context.go(
                  ['/dashboard', '/products', '/orders', '/clients', '/stock'][i],
                ),
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), label: 'Главная'),
                  NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Товары'),
                  NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Заказы'),
                  NavigationDestination(icon: Icon(Icons.people_outline), label: 'Клиенты'),
                  NavigationDestination(icon: Icon(Icons.warehouse_outlined), label: 'Склад'),
                ],
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
                  _StatCard(title: 'Заказы', value: '${stats.ordersCount}', hint: 'Всего создано', icon: Icons.receipt_long_outlined),
                  _StatCard(title: 'Выручка', value: money(stats.totalSales), hint: 'Сумма продаж', icon: Icons.currency_ruble_rounded),
                  _StatCard(title: 'Не оплачено', value: '${stats.unpaidOrdersCount}', hint: 'Требует контроля', icon: Icons.pending_actions_outlined),
                  _StatCard(title: 'Низкий остаток', value: '${stats.lowStockCount}', hint: 'Нужна закупка', icon: Icons.warning_amber_rounded),
                ],
              ),
              const SizedBox(height: 14),
              _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle(
                      title: 'Быстрые действия',
                      subtitle: 'Частые сценарии, чтобы не переключаться между экранами вручную.',
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _QuickActionButton(icon: Icons.add_shopping_cart_rounded, label: 'Создать заказ', onTap: () => context.push('/create-order')),
                        _QuickActionButton(icon: Icons.inventory_2_outlined, label: 'Открыть товары', onTap: () => context.go('/products')),
                        _QuickActionButton(icon: Icons.receipt_long_outlined, label: 'История заказов', onTap: () => context.go('/orders')),
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
                      final categoryField = DropdownButtonFormField<String>(
                        initialValue: s.category,
                        hint: const Text('Категория'),
                        items: s.items.map((e) => e.category).toSet().map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(growable: false),
                        onChanged: context.read<ProductsCubit>().setCategory,
                      );
                      final brandField = DropdownButtonFormField<String>(
                        initialValue: s.brand,
                        hint: const Text('Бренд'),
                        items: s.items.map((e) => e.brand).toSet().map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(growable: false),
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
                      subtitle: 'Измените фильтры или попробуйте другой поисковый запрос.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 124),
                      itemCount: s.filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _ProductTile(product: s.filtered[i]),
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
  static const MethodChannel _xmlPickerChannel = MethodChannel('crm/xml_picker');

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
                    SnackBar(content: Text('Заказ ${createdOrder.orderNumber} успешно создан.')),
                  );
                  context.go('/orders');
                }
                if (s.error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(s.error!)),
                  );
                }
              },
              builder: (context, s) => Column(
                children: [
                  _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionTitle(
                          title: 'Импорт из Google Sheets',
                          subtitle: 'Можно вставить как содержимое таблицы, так и публичную ссылку на Google Sheets.',
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () => _showImportDialog(context),
                              icon: const Icon(Icons.content_paste_go_rounded),
                              label: const Text('Вставить таблицу или ссылку'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => context.go('/products'),
                              icon: const Icon(Icons.inventory_2_outlined),
                              label: const Text('Добавить товары вручную'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Panel(
                    child: Column(
                      children: [
                        BlocBuilder<ClientsCubit, List<Client>>(
                          builder: (_, clients) => DropdownButtonFormField<String>(
                            initialValue: s.client?.id,
                            hint: const Text('Клиент'),
                            items: clients.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(growable: false),
                            onChanged: (id) => context.read<OrderDraftCubit>().pickClient(
                                  clients.where((c) => c.id == id).firstOrNull,
                                ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<PaymentStatus>(
                          initialValue: s.paymentStatus,
                          items: PaymentStatus.values.map((e) => DropdownMenuItem(value: e, child: Text(pStatus(e)))).toList(growable: false),
                          onChanged: (v) => context.read<OrderDraftCubit>().setPayment(v ?? PaymentStatus.unpaid),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: ValueKey('comment-${s.comment}'),
                          initialValue: s.comment,
                          onChanged: context.read<OrderDraftCubit>().setComment,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(labelText: 'Комментарий к заказу'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: s.lines.isEmpty
                        ? const _EmptyPanel(
                            icon: Icons.shopping_cart_outlined,
                            title: 'Черновик пока пуст',
                            subtitle: 'Добавьте товары вручную или импортируйте таблицу из Google Sheets.',
                          )
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: s.lines.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (_, i) => _DraftLineTile(line: s.lines[i]),
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
                            onPressed: () => context.read<OrderDraftCubit>().createOrder(),
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
        title: const Text('Импорт из Google Sheets'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Вставьте ссылку, текст таблицы или выберите XML файл заказа.',
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 10,
                maxLines: 16,
                decoration: const InputDecoration(
                  hintText: 'Например: ссылка docs.google.com/... или строки таблицы с колонками Товар / SKU / Количество',
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop('__pick_xml_file__'),
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('XML файл'),
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
    if (importInput == '__pick_xml_file__') {
      try {
        importInput = await _pickXmlFileText();
      } on FormatException catch (e) {
        if (!context.mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text(e.message)),
        );
        return;
      }
    }

    if (importInput == null || importInput.trim().isEmpty) return;

    final products = context.read<ProductsCubit>().state.items;
    final clients = context.read<ClientsCubit>().state;
    final draftCubit = context.read<OrderDraftCubit>();

    try {
      var importPayload = importInput.trim();
      final linkUris = googleSheetsCsvUris(importPayload);
      if (linkUris.isNotEmpty) {
        String? loadedBody;
        for (final linkUri in linkUris) {
          try {
            final response = await Dio().getUri<String>(
              linkUri,
              options: Options(
                responseType: ResponseType.plain,
                followRedirects: true,
                validateStatus: (status) =>
                    status != null && status >= 200 && status < 400,
                headers: const {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36',
                  'Accept':
                      'text/csv,text/tab-separated-values,text/plain,application/json,text/html;q=0.9,*/*;q=0.8',
                },
              ),
            );
            final body = response.data?.trim();
            final normalizedBody =
                body == null ? null : normalizeImportedTablePayload(body);
            if (normalizedBody != null && normalizedBody.isNotEmpty) {
              loadedBody = normalizedBody;
              break;
            }
          } on DioException {
            continue;
          }
        }
        if (loadedBody == null) {
          final authResult =
              await GoogleSheetsAuthLoader.instance.loadViaGoogleAuth(linkUris);
          loadedBody = authResult.payload;
          if (loadedBody == null) {
            throw FormatException(
              authResult.errorMessage ??
                  'Не удалось прочитать таблицу по ссылке даже после входа через Google.',
            );
          }
        }
        importPayload = loadedBody;
      }

      final message = draftCubit.importTableText(
            raw: importPayload,
            products: products,
            clients: clients,
          );
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(message)),
      );
    } on FormatException catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<String> _pickXmlFileText() async {
    if (!Platform.isAndroid) {
      throw const FormatException(
        '????? XML ????? ?????? ?????????????? ?????? ?? Android.',
      );
    }

    final raw = await _xmlPickerChannel.invokeMethod<String>('pickXmlText');
    if (raw == null) {
      throw const FormatException('????? ????? ???????.');
    }

    final decoded = raw.trim();
    if (decoded.isEmpty) {
      throw const FormatException('XML ???? ??????.');
    }
    if (!decoded.contains('<') || !decoded.contains('>')) {
      throw const FormatException('????????? ???? ?? ????? ?? XML.');
    }
    return decoded;
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
                subtitle: 'Создайте первый заказ вручную или импортируйте таблицу.',
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

  @override
  Widget build(BuildContext context) {
    final order = context.select(
      (OrdersCubit c) => c.state.where((o) => o.id == id).firstOrNull,
    );
    return _Background(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(order?.orderNumber ?? 'Заказ')),
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
                : ListView(
                    children: [
                      _Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(order.clientName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                            const SizedBox(height: 6),
                            Text(date(order.date), style: const TextStyle(color: Colors.white70)),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _MiniBadge(icon: Icons.payments_outlined, label: pStatus(order.paymentStatus)),
                                _MiniBadge(icon: Icons.currency_ruble_rounded, label: 'Сумма ${money(order.totalAmount)}'),
                                _MiniBadge(icon: Icons.trending_up_rounded, label: 'Прибыль ${money(order.profit)}'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...order.items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _Panel(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 6),
                                      Text('${item.quantity} шт. x ${money(item.salePrice)}', style: const TextStyle(color: Colors.white70)),
                                    ],
                                  ),
                                ),
                                Text(money(item.lineTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
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
                _Avatar(initial: clients[i].name.isEmpty ? 'К' : clients[i].name[0]),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(clients[i].name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(clients[i].phone, style: const TextStyle(color: Colors.white70)),
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
                      Text(products[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text('Остаток ${products[i].stock} / минимум ${products[i].minStock}', style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                _MiniBadge(icon: Icons.warehouse_outlined, label: stockStatus(products[i])),
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
                    Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: Colors.white70)),
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
            subtitle: 'Оперативный блок с главным фокусом по продажам и остаткам.',
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
                    const Text('Выручка за период', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 8),
                    Text(money(stats.totalSales), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Text('Неоплаченных заказов: ${stats.unpaidOrdersCount}', style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              );
              final sideCards = Column(
                children: [
                  _CompactInfo(title: 'Низкий остаток', value: '${stats.lowStockCount}'),
                  const SizedBox(height: 10),
                  _CompactInfo(title: 'Всего заказов', value: '${stats.ordersCount}'),
                ],
              );
              if (vertical) {
                return Column(
                  children: [
                    salesCard,
                    const SizedBox(height: 12),
                    sideCards,
                  ],
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
              Text(product.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniBadge(icon: Icons.sell_outlined, label: product.brand),
                  _MiniBadge(icon: Icons.tag_outlined, label: product.sku ?? 'Без SKU'),
                  _MiniBadge(icon: Icons.inventory_2_outlined, label: stockStatus(product)),
                ],
              ),
            ],
          );
          final aside = Column(
            crossAxisAlignment: vertical ? CrossAxisAlignment.start : CrossAxisAlignment.end,
            children: [
              Text(money(product.salePrice), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 6),
              Text('В наличии: ${product.stock}', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 10),
              FilledButton.tonal(
                onPressed: product.stock <= 0 ? null : () => context.read<OrderDraftCubit>().addProduct(product),
                child: const Text('Добавить'),
              ),
            ],
          );
          if (vertical) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: 14),
                aside,
              ],
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
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(line.product.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              Text('${money(line.product.salePrice)} за шт.', style: const TextStyle(color: Colors.white70)),
            ],
          );
          final controls = Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              IconButton(
                onPressed: () => context.read<OrderDraftCubit>().setQty(line.product.id, line.quantity - 1),
                icon: const Icon(Icons.remove_rounded),
              ),
              Text('${line.quantity}', style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(
                onPressed: () => context.read<OrderDraftCubit>().setQty(line.product.id, line.quantity + 1),
                icon: const Icon(Icons.add_rounded),
              ),
              IconButton(
                onPressed: () => context.read<OrderDraftCubit>().remove(line.product.id),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          );
          if (vertical) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                info,
                const SizedBox(height: 12),
                controls,
              ],
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
                Text(order.orderNumber, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                Text(order.clientName),
                const SizedBox(height: 4),
                Text('${date(order.date)} • ${pStatus(order.paymentStatus)}', style: const TextStyle(color: Colors.white70)),
              ],
            );
            final moneyInfo = Column(
              crossAxisAlignment: vertical ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: [
                Text(money(order.totalAmount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 4),
                Text('Прибыль ${money(order.profit)}', style: const TextStyle(color: Color(0xFF7ED9A4))),
              ],
            );
            if (vertical) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  mainInfo,
                  const SizedBox(height: 14),
                  moneyInfo,
                ],
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
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: Colors.white70, height: 1.4)),
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
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
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
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(label),
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
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(subtitle, style: const TextStyle(color: Colors.white70, height: 1.4), textAlign: TextAlign.center),
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
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
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
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
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
          const Positioned(top: -70, right: -40, child: _Glow(color: Color(0xFFF18B54), size: 220)),
          const Positioned(top: 160, left: -30, child: _Glow(color: Color(0xFF6EC6CA), size: 180)),
          const Positioned(bottom: -30, right: 30, child: _Glow(color: Color(0xFF5C7CFA), size: 190)),
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


