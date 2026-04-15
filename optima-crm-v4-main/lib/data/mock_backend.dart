import 'dart:convert';

import 'package:crm/domain/entities/entities.dart';
import 'package:crm/domain/repositories/repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockBackend
    implements
        ProductRepository,
        ClientRepository,
        OrderRepository,
        DashboardRepository {
  MockBackend._();

  static const _kProducts = 'db_products_v1';
  static const _kClients = 'db_clients_v1';
  static const _kOrders = 'db_orders_v1';

  late SharedPreferences _prefs;
  late List<Product> _products;
  late List<Client> _clients;
  late List<Order> _orders;

  static Future<MockBackend> create() async {
    final b = MockBackend._();
    b._prefs = await SharedPreferences.getInstance();
    // Set defaults
    b._products = [
      Product(id: 'p1', sku: 'SKU-001', name: 'iPhone 14 128GB', category: 'Phones', brand: 'Apple', salePrice: 780, purchasePrice: 690, stock: 8, minStock: 3, isNew: true),
      Product(id: 'p2', sku: 'SKU-002', name: 'Galaxy S24', category: 'Phones', brand: 'Samsung', salePrice: 690, purchasePrice: 610, stock: 2, minStock: 3),
      Product(id: 'p3', sku: 'SKU-003', name: 'Redmi Note', category: 'Phones', brand: 'Xiaomi', salePrice: 210, purchasePrice: 170, stock: 0, minStock: 4),
      Product(id: 'p4', sku: 'SKU-004', name: 'AirPods Pro', category: 'Accessories', brand: 'Apple', salePrice: 230, purchasePrice: 180, stock: 21, minStock: 7),
    ];
    b._clients = [
      Client(id: 'c1', name: 'Tech Store', phone: '+996700111222', comment: 'Main reseller', createdAt: DateTime(2025, 10, 1)),
      Client(id: 'c2', name: 'Mobile Point', phone: '+996700333444', createdAt: DateTime(2025, 12, 1)),
    ];
    b._orders = [];
    await b._load();
    return b;
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      final productsJson = _prefs.getString(_kProducts);
      if (productsJson != null) {
        final list = jsonDecode(productsJson) as List<dynamic>;
        _products = list
            .map((j) => _productFromJson(j as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      // Keep defaults on corrupt data
    }

    try {
      final clientsJson = _prefs.getString(_kClients);
      if (clientsJson != null) {
        final list = jsonDecode(clientsJson) as List<dynamic>;
        _clients = list
            .map((j) => _clientFromJson(j as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    try {
      final ordersJson = _prefs.getString(_kOrders);
      if (ordersJson != null) {
        final list = jsonDecode(ordersJson) as List<dynamic>;
        _orders = list
            .map((j) => _orderFromJson(j as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
  }

  Future<void> _saveProducts() async {
    await _prefs.setString(
      _kProducts,
      jsonEncode(_products.map(_productToJson).toList()),
    );
  }

  Future<void> _saveClients() async {
    await _prefs.setString(
      _kClients,
      jsonEncode(_clients.map(_clientToJson).toList()),
    );
  }

  Future<void> _saveOrders() async {
    await _prefs.setString(
      _kOrders,
      jsonEncode(_orders.map(_orderToJson).toList()),
    );
  }

  // ── Serialization ─────────────────────────────────────────────────────────

  static Map<String, dynamic> _productToJson(Product p) => {
        'id': p.id,
        'sku': p.sku,
        'name': p.name,
        'category': p.category,
        'brand': p.brand,
        'salePrice': p.salePrice,
        'purchasePrice': p.purchasePrice,
        'stock': p.stock,
        'minStock': p.minStock,
        'isNew': p.isNew,
        'createdAt': p.createdAt?.toIso8601String(),
      };

  static Product _productFromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String,
        sku: j['sku'] as String?,
        name: j['name'] as String,
        category: j['category'] as String,
        brand: j['brand'] as String,
        salePrice: (j['salePrice'] as num).toDouble(),
        purchasePrice: (j['purchasePrice'] as num).toDouble(),
        stock: j['stock'] as int,
        minStock: j['minStock'] as int,
        isNew: (j['isNew'] as bool?) ?? false,
        createdAt: j['createdAt'] != null
            ? DateTime.parse(j['createdAt'] as String)
            : null,
      );

  static Map<String, dynamic> _clientToJson(Client c) => {
        'id': c.id,
        'name': c.name,
        'phone': c.phone,
        'comment': c.comment,
        'createdAt': c.createdAt.toIso8601String(),
      };

  static Client _clientFromJson(Map<String, dynamic> j) => Client(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String,
        comment: j['comment'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );

  static Map<String, dynamic> _orderItemToJson(OrderItem i) => {
        'id': i.id,
        'orderId': i.orderId,
        'productId': i.productId,
        'productName': i.productName,
        'quantity': i.quantity,
        'salePrice': i.salePrice,
        'purchasePrice': i.purchasePrice,
      };

  static OrderItem _orderItemFromJson(Map<String, dynamic> j) => OrderItem(
        id: j['id'] as String,
        orderId: j['orderId'] as String,
        productId: j['productId'] as String,
        productName: j['productName'] as String,
        quantity: j['quantity'] as int,
        salePrice: (j['salePrice'] as num).toDouble(),
        purchasePrice: (j['purchasePrice'] as num).toDouble(),
      );

  static Map<String, dynamic> _orderToJson(Order o) => {
        'id': o.id,
        'orderNumber': o.orderNumber,
        'date': o.date.toIso8601String(),
        'clientId': o.clientId,
        'clientName': o.clientName,
        'items': o.items.map(_orderItemToJson).toList(),
        'paymentStatus': o.paymentStatus.name,
        'comment': o.comment,
        'createdAt': o.createdAt.toIso8601String(),
      };

  static Order _orderFromJson(Map<String, dynamic> j) => Order(
        id: j['id'] as String,
        orderNumber: j['orderNumber'] as String,
        date: DateTime.parse(j['date'] as String),
        clientId: j['clientId'] as String,
        clientName: j['clientName'] as String,
        items: (j['items'] as List<dynamic>)
            .map((i) => _orderItemFromJson(i as Map<String, dynamic>))
            .toList(growable: false),
        paymentStatus: PaymentStatus.values.byName(j['paymentStatus'] as String),
        comment: j['comment'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );

  // ── Repository methods ────────────────────────────────────────────────────

  @override
  Future<Order> createOrder(CreateOrderInput input) async {
    final now = DateTime.now();
    final orderId = 'o${now.microsecondsSinceEpoch}';

    for (final item in input.items) {
      if (item.productId.startsWith('adhoc::')) continue;
      final product =
          _products.where((p) => p.id == item.productId).firstOrNull;
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
          .map(
            (i) => OrderItem(
              id: '${i.productId}-$orderId',
              orderId: orderId,
              productId: i.productId,
              productName: i.productName,
              quantity: i.quantity,
              salePrice: i.salePrice,
              purchasePrice: i.purchasePrice,
            ),
          )
          .toList(growable: false),
      paymentStatus: input.paymentStatus,
      comment: input.comment,
      createdAt: now,
    );

    for (final item in order.items) {
      final idx = _products.indexWhere((p) => p.id == item.productId);
      if (idx >= 0) {
        _products[idx] = _products[idx]
            .copyWith(stock: _products[idx].stock - item.quantity);
      }
    }
    _orders.insert(0, order);

    await _saveOrders();
    await _saveProducts();
    return order;
  }

  @override
  Future<Client> createClient({
    required String name,
    required String phone,
    String? comment,
  }) async {
    final client = Client(
      id: 'c${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      phone: phone,
      comment: comment,
      createdAt: DateTime.now(),
    );
    _clients.insert(0, client);
    await _saveClients();
    return client;
  }

  @override
  Future<DashboardStats> getDashboardStats() async {
    final totalSales =
        _orders.fold<double>(0, (sum, o) => sum + o.totalAmount);
    final unpaid = _orders
        .where((o) => o.paymentStatus == PaymentStatus.unpaid)
        .length;
    final low = _products
        .where(
          (p) =>
              p.status == ProductAvailabilityStatus.lowStock ||
              p.status == ProductAvailabilityStatus.outOfStock,
        )
        .length;
    return DashboardStats(
      ordersCount: _orders.length,
      totalSales: totalSales,
      unpaidOrdersCount: unpaid,
      lowStockCount: low,
    );
  }

  @override
  Future<List<Client>> getClients() async => List.unmodifiable(_clients);

  @override
  Future<List<Order>> getOrders() async => List.unmodifiable(_orders);

  @override
  Future<Order?> getOrderById(String id) async =>
      _orders.where((o) => o.id == id).firstOrNull;

  @override
  Future<List<Product>> getLowStockProducts() async {
    return _products
        .where(
          (p) =>
              p.status == ProductAvailabilityStatus.lowStock ||
              p.status == ProductAvailabilityStatus.outOfStock,
        )
        .toList(growable: false);
  }

  @override
  Future<List<Product>> getProducts() async => List.unmodifiable(_products);

  @override
  Future<Order?> updatePaymentStatus(
    String orderId,
    PaymentStatus status,
  ) async {
    final i = _orders.indexWhere((o) => o.id == orderId);
    if (i < 0) return null;
    _orders[i] = _orders[i].copyWith(paymentStatus: status);
    await _saveOrders();
    return _orders[i];
  }

  @override
  Future<void> deleteOrder(String id) async {
    _orders.removeWhere((o) => o.id == id);
    await _saveOrders();
  }
}
