import 'package:equatable/equatable.dart';

enum PaymentStatus { paid, unpaid }

enum ProductAvailabilityStatus { inStock, lowStock, outOfStock, newProduct }

class Product extends Equatable {
  const Product({
    required this.id,
    this.sku,
    required this.name,
    required this.category,
    required this.brand,
    required this.salePrice,
    required this.purchasePrice,
    required this.stock,
    required this.minStock,
    this.isNew = false,
    this.createdAt,
  });

  final String id;
  final String? sku;
  final String name;
  final String category;
  final String brand;
  final double salePrice;
  final double purchasePrice;
  final int stock;
  final int minStock;
  final bool isNew;
  final DateTime? createdAt;

  ProductAvailabilityStatus get status {
    if (isNew) return ProductAvailabilityStatus.newProduct;
    if (stock <= 0) return ProductAvailabilityStatus.outOfStock;
    if (stock <= minStock) return ProductAvailabilityStatus.lowStock;
    return ProductAvailabilityStatus.inStock;
  }

  Product copyWith({int? stock, bool? isNew, double? salePrice, double? purchasePrice}) {
    return Product(
      id: id,
      sku: sku,
      name: name,
      category: category,
      brand: brand,
      salePrice: salePrice ?? this.salePrice,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      stock: stock ?? this.stock,
      minStock: minStock,
      isNew: isNew ?? this.isNew,
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props => [id, sku, name, category, brand, salePrice, purchasePrice, stock, minStock, isNew, createdAt];
}

class Client extends Equatable {
  const Client({required this.id, required this.name, required this.phone, this.comment, required this.createdAt});

  final String id;
  final String name;
  final String phone;
  final String? comment;
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, name, phone, comment, createdAt];
}

class OrderItem extends Equatable {
  const OrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.salePrice,
    required this.purchasePrice,
  });

  final String id;
  final String orderId;
  final String productId;
  final String productName;
  final int quantity;
  final double salePrice;
  final double purchasePrice;

  double get lineTotal => quantity * salePrice;
  double get lineCost => quantity * purchasePrice;
  double get lineProfit => lineTotal - lineCost;

  @override
  List<Object?> get props => [id, orderId, productId, productName, quantity, salePrice, purchasePrice];
}

class Order extends Equatable {
  const Order({
    required this.id,
    required this.orderNumber,
    required this.date,
    required this.clientId,
    required this.clientName,
    required this.items,
    required this.paymentStatus,
    this.comment,
    required this.createdAt,
  });

  final String id;
  final String orderNumber;
  final DateTime date;
  final String clientId;
  final String clientName;
  final List<OrderItem> items;
  final PaymentStatus paymentStatus;
  final String? comment;
  final DateTime createdAt;

  int get itemsCount => items.length;
  int get totalQuantity => items.fold(0, (sum, i) => sum + i.quantity);
  double get totalAmount => items.fold(0, (sum, i) => sum + i.lineTotal);
  double get totalCost => items.fold(0, (sum, i) => sum + i.lineCost);
  double get profit => totalAmount - totalCost;

  Order copyWith({PaymentStatus? paymentStatus}) => Order(
        id: id,
        orderNumber: orderNumber,
        date: date,
        clientId: clientId,
        clientName: clientName,
        items: items,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        comment: comment,
        createdAt: createdAt,
      );

  @override
  List<Object?> get props => [id, orderNumber, date, clientId, clientName, items, paymentStatus, comment, createdAt];
}

class DashboardStats extends Equatable {
  const DashboardStats({
    required this.ordersCount,
    required this.totalSales,
    required this.unpaidOrdersCount,
    required this.lowStockCount,
  });

  final int ordersCount;
  final double totalSales;
  final int unpaidOrdersCount;
  final int lowStockCount;

  @override
  List<Object?> get props => [ordersCount, totalSales, unpaidOrdersCount, lowStockCount];
}
