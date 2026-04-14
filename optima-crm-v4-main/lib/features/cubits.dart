import 'package:crm/domain/entities/entities.dart';
import 'package:crm/domain/repositories/repositories.dart';
import 'package:crm/features/order_import.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ProductsState extends Equatable {
  const ProductsState({
    this.loading = false,
    this.items = const [],
    this.search = '',
    this.category,
    this.brand,
  });

  final bool loading;
  final List<Product> items;
  final String search;
  final String? category;
  final String? brand;

  List<Product> get filtered => items.where((p) {
        final q = search.toLowerCase();
        return (q.isEmpty ||
                p.name.toLowerCase().contains(q) ||
                (p.sku ?? '').toLowerCase().contains(q)) &&
            (category == null || p.category == category) &&
            (brand == null || p.brand == brand);
      }).toList(growable: false);

  @override
  List<Object?> get props => [loading, items, search, category, brand];
}

class ProductsCubit extends Cubit<ProductsState> {
  ProductsCubit(this.repo) : super(const ProductsState());

  final ProductRepository repo;

  Future<void> load() async => emit(
        ProductsState(
          items: await repo.getProducts(),
          search: state.search,
          category: state.category,
          brand: state.brand,
        ),
      );

  void setSearch(String s) => emit(
        ProductsState(
          items: state.items,
          search: s,
          category: state.category,
          brand: state.brand,
        ),
      );

  void setCategory(String? s) => emit(
        ProductsState(
          items: state.items,
          search: state.search,
          category: s,
          brand: state.brand,
        ),
      );

  void setBrand(String? s) => emit(
        ProductsState(
          items: state.items,
          search: state.search,
          category: state.category,
          brand: s,
        ),
      );
}

class ClientsCubit extends Cubit<List<Client>> {
  ClientsCubit(this.repo) : super(const []);

  final ClientRepository repo;

  Future<void> load() async => emit(await repo.getClients());
}

class OrdersCubit extends Cubit<List<Order>> {
  OrdersCubit(this.repo) : super(const []);

  final OrderRepository repo;

  Future<void> load() async => emit(await repo.getOrders());

  Future<void> delete(String id) async {
    await repo.deleteOrder(id);
    emit(state.where((o) => o.id != id).toList(growable: false));
  }
}

class DashboardCubit extends Cubit<DashboardStats?> {
  DashboardCubit(this.repo) : super(null);

  final DashboardRepository repo;

  Future<void> load() async => emit(await repo.getDashboardStats());
}

class StockCubit extends Cubit<List<Product>> {
  StockCubit(this.repo) : super(const []);

  final ProductRepository repo;

  Future<void> load() async => emit(await repo.getProducts());
}

class DraftLine extends Equatable {
  const DraftLine({required this.product, required this.quantity});

  final Product product;
  final int quantity;

  DraftLine copyWith({int? quantity}) =>
      DraftLine(product: product, quantity: quantity ?? this.quantity);

  @override
  List<Object?> get props => [product, quantity];
}

class OrderDraftState extends Equatable {
  const OrderDraftState({
    this.lines = const [],
    this.client,
    this.paymentStatus = PaymentStatus.unpaid,
    this.comment = '',
    this.submitting = false,
    this.createdOrder,
    this.error,
  });

  final List<DraftLine> lines;
  final Client? client;
  final PaymentStatus paymentStatus;
  final String comment;
  final bool submitting;
  final Order? createdOrder;
  final String? error;

  int get itemsCount => lines.length;
  int get totalQuantity => lines.fold(0, (sum, i) => sum + i.quantity);
  double get totalAmount =>
      lines.fold(0, (sum, i) => sum + i.quantity * i.product.salePrice);
  double get totalCost =>
      lines.fold(0, (sum, i) => sum + i.quantity * i.product.purchasePrice);
  double get profit => totalAmount - totalCost;

  @override
  List<Object?> get props => [
        lines,
        client,
        paymentStatus,
        comment,
        submitting,
        createdOrder,
        error,
      ];
}

class OrderDraftCubit extends Cubit<OrderDraftState> {
  OrderDraftCubit(this.repo) : super(const OrderDraftState());

  final OrderRepository repo;

  void _emitState({
    List<DraftLine>? lines,
    Client? client,
    bool resetClient = false,
    PaymentStatus? paymentStatus,
    String? comment,
    bool submitting = false,
    Order? createdOrder,
    String? error,
  }) {
    emit(
      OrderDraftState(
        lines: lines ?? state.lines,
        client: resetClient ? null : (client ?? state.client),
        paymentStatus: paymentStatus ?? state.paymentStatus,
        comment: comment ?? state.comment,
        submitting: submitting,
        createdOrder: createdOrder,
        error: error,
      ),
    );
  }

  void addProduct(Product p) {
    final i = state.lines.indexWhere((e) => e.product.id == p.id);
    if (i < 0) {
      _emitState(lines: [...state.lines, DraftLine(product: p, quantity: 1)]);
      return;
    }

    final next = [...state.lines];
    if (next[i].quantity >= p.stock) {
      _emitState(error: 'Нельзя добавить больше, чем есть на складе.');
      return;
    }

    next[i] = next[i].copyWith(quantity: next[i].quantity + 1);
    _emitState(lines: next, error: null);
  }

  void setQty(String productId, int qty) {
    if (qty <= 0) {
      remove(productId);
      return;
    }

    final line = state.lines.where((e) => e.product.id == productId).firstOrNull;
    if (line == null) return;
    if (qty > line.product.stock) {
      _emitState(error: 'На складе доступно только ${line.product.stock} шт.');
      return;
    }

    final next = state.lines
        .map((e) => e.product.id == productId ? e.copyWith(quantity: qty) : e)
        .toList(growable: false);
    _emitState(lines: next, error: null);
  }

  void remove(String productId) => _emitState(
        lines: state.lines
            .where((e) => e.product.id != productId)
            .toList(growable: false),
        error: null,
      );

  void pickClient(Client? c) =>
      _emitState(client: c, resetClient: c == null, error: null);

  void setPayment(PaymentStatus s) =>
      _emitState(paymentStatus: s, error: null);

  void setComment(String c) => _emitState(comment: c, error: null);

  String importTableText({
    required String raw,
    required List<Product> products,
    required List<Client> clients,
  }) {
    final imported = parseImportedOrder(raw);
    // key → DraftLine; key is product.id for catalog hits, lookup text for ad-hoc
    final aggregated = <String, DraftLine>{};
    var catalogCount = 0;
    var adHocCount = 0;

    for (final importedLine in imported.lines) {
      final catalogProduct = findMatchingProduct(products, importedLine.lookup);

      if (catalogProduct != null) {
        // Found in catalog — respect stock limits and use catalog prices
        catalogCount++;
        final current = aggregated[catalogProduct.id];
        final requestedQty = (current?.quantity ?? 0) + importedLine.quantity;
        aggregated[catalogProduct.id] = DraftLine(
          product: catalogProduct,
          quantity:
              requestedQty > catalogProduct.stock
                  ? catalogProduct.stock
                  : requestedQty,
        );
      } else {
        // Not in catalog — create an ad-hoc line directly from table data.
        // Use the lookup string as the stable key so duplicate rows are merged.
        adHocCount++;
        final key = 'adhoc::${importedLine.lookup}';
        final current = aggregated[key];
        final mergedQty = (current?.quantity ?? 0) + importedLine.quantity;
        final adHocProduct = Product(
          id: key,
          name: importedLine.lookup,
          category: '',
          brand: '',
          salePrice: importedLine.salePrice ?? 0,
          purchasePrice: importedLine.purchasePrice ?? 0,
          // No real stock — allow any quantity from the import
          stock: 999999,
          minStock: 0,
        );
        aggregated[key] = DraftLine(product: adHocProduct, quantity: mergedQty);
      }
    }

    final nextLines = aggregated.values.toList(growable: false);
    if (nextLines.isEmpty) {
      throw const FormatException(
        'Не удалось распознать ни одной позиции из таблицы.',
      );
    }

    final matchedClient = findMatchingClient(clients, imported.clientName);
    _emitState(
      lines: nextLines,
      client: matchedClient ?? state.client,
      paymentStatus: imported.paymentStatus ?? state.paymentStatus,
      comment: imported.comment ?? state.comment,
      error: null,
    );

    if (catalogCount == 0) {
      return 'Импортировано ${nextLines.length} позиций из таблицы.';
    }
    if (adHocCount == 0) {
      return 'Импортировано ${nextLines.length} позиций из каталога.';
    }
    return 'Импортировано ${nextLines.length} позиций '
        '($catalogCount из каталога, $adHocCount из таблицы).';
  }

  Future<Order?> createOrder() async {
    if (state.lines.isEmpty) {
      _emitState(error: 'Добавьте хотя бы один товар.');
      return null;
    }
    if (state.client == null) {
      _emitState(error: 'Выберите клиента.');
      return null;
    }

    final exceededLine = state.lines
        .where((line) =>
            !line.product.id.startsWith('adhoc::') &&
            line.quantity > line.product.stock)
        .firstOrNull;
    if (exceededLine != null) {
      _emitState(
        error: 'Недостаточно остатка для "${exceededLine.product.name}".',
      );
      return null;
    }

    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final items = state.lines
        .map(
          (l) => OrderItem(
            id: '${l.product.id}-$tempId',
            orderId: tempId,
            productId: l.product.id,
            productName: l.product.name,
            quantity: l.quantity,
            salePrice: l.product.salePrice,
            purchasePrice: l.product.purchasePrice,
          ),
        )
        .toList(growable: false);

    try {
      final created = await repo.createOrder(
        CreateOrderInput(
          clientId: state.client!.id,
          clientName: state.client!.name,
          items: items,
          paymentStatus: state.paymentStatus,
          comment: state.comment.isEmpty ? null : state.comment,
        ),
      );
      emit(OrderDraftState(createdOrder: created));
      return created;
    } on StateError catch (e) {
      _emitState(error: e.message.toString());
      return null;
    }
  }

  void clearCreated() => emit(const OrderDraftState());
}

