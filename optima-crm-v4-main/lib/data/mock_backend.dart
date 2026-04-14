import 'package:crm/domain/entities/entities.dart';
import 'package:crm/domain/repositories/repositories.dart';

class MockBackend implements ProductRepository, ClientRepository, OrderRepository, DashboardRepository {
  final List<Product> _products = [
    Product(id: 'p1', sku: 'SKU-001', name: 'iPhone 14 128GB', category: 'Phones', brand: 'Apple', salePrice: 780, purchasePrice: 690, stock: 8, minStock: 3, isNew: true),
    Product(id: 'p2', sku: 'SKU-002', name: 'Galaxy S24', category: 'Phones', brand: 'Samsung', salePrice: 690, purchasePrice: 610, stock: 2, minStock: 3),
    Product(id: 'p3', sku: 'SKU-003', name: 'Redmi Note', category: 'Phones', brand: 'Xiaomi', salePrice: 210, purchasePrice: 170, stock: 0, minStock: 4),
    Product(id: 'p4', sku: 'SKU-004', name: 'AirPods Pro', category: 'Accessories', brand: 'Apple', salePrice: 230, purchasePrice: 180, stock: 21, minStock: 7),
  ];

  final List<Client> _clients = [
    Client(id: 'c1', name: 'Tech Store', phone: '+996700111222', comment: 'Main reseller', createdAt: DateTime(2025, 10, 1)),
    Client(id: 'c2', name: 'Mobile Point', phone: '+996700333444', createdAt: DateTime(2025, 12, 1)),
  ];

  final List<Order> _orders = [];

  @override
  Future<Order> createOrder(CreateOrderInput input) async {
    final now = DateTime.now();
    final orderId = 'o${now.microsecondsSinceEpoch}';

    for (final item in input.items) {
      // Ad-hoc lines (imported directly from a table, not in catalog) are
      // allowed through without stock validation — their id starts with 'adhoc::'
      if (item.productId.startsWith('adhoc::')) continue;

      final product = _products.where((p) => p.id == item.productId).firstOrNull;
      if (product == null) {
        throw StateError('Product ${item.productId} not found');
      }
      if (item.quantity > product.stock) {
        throw StateError('Not enough stock for ${product.name}');
      }
    }

    final order = Order(
      id: orderId,
      orderNumber: 'INV-${now.millisecondsSinceEpoch}',
      date: now,
      clientId: input.clientId,
      clientName: input.clientName,
      items: input.items
          .map((i) => OrderItem(
                id: '${i.productId}-$orderId',
                orderId: orderId,
                productId: i.productId,
                productName: i.productName,
                quantity: i.quantity,
                salePrice: i.salePrice,
                purchasePrice: i.purchasePrice,
              ))
          .toList(growable: false),
      paymentStatus: input.paymentStatus,
      comment: input.comment,
      createdAt: now,
    );
    for (final item in order.items) {
      final idx = _products.indexWhere((p) => p.id == item.productId);
      if (idx >= 0) {
        _products[idx] = _products[idx].copyWith(stock: _products[idx].stock - item.quantity);
      }
    }
    _orders.insert(0, order);
    return order;
  }

  @override
  Future<Client> createClient({required String name, required String phone, String? comment}) async {
    final client = Client(id: 'c${DateTime.now().microsecondsSinceEpoch}', name: name, phone: phone, comment: comment, createdAt: DateTime.now());
    _clients.insert(0, client);
    return client;
  }

  @override
  Future<DashboardStats> getDashboardStats() async {
    final totalSales = _orders.fold<double>(0, (sum, o) => sum + o.totalAmount);
    final unpaid = _orders.where((o) => o.paymentStatus == PaymentStatus.unpaid).length;
    final low = _products.where((p) => p.status == ProductAvailabilityStatus.lowStock || p.status == ProductAvailabilityStatus.outOfStock).length;
    return DashboardStats(ordersCount: _orders.length, totalSales: totalSales, unpaidOrdersCount: unpaid, lowStockCount: low);
  }

  @override
  Future<List<Client>> getClients() async => List.unmodifiable(_clients);

  @override
  Future<List<Order>> getOrders() async => List.unmodifiable(_orders);

  @override
  Future<Order?> getOrderById(String id) async => _orders.where((o) => o.id == id).firstOrNull;

  @override
  Future<List<Product>> getLowStockProducts() async {
    return _products.where((p) => p.status == ProductAvailabilityStatus.lowStock || p.status == ProductAvailabilityStatus.outOfStock).toList(growable: false);
  }

  @override
  Future<List<Product>> getProducts() async => List.unmodifiable(_products);

  @override
  Future<Order?> updatePaymentStatus(String orderId, PaymentStatus status) async {
    final i = _orders.indexWhere((o) => o.id == orderId);
    if (i < 0) return null;
    _orders[i] = _orders[i].copyWith(paymentStatus: status);
    return _orders[i];
  }

  @override
  Future<void> deleteOrder(String id) async {
    _orders.removeWhere((o) => o.id == id);
  }
}
