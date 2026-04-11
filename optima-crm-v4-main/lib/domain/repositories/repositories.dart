import 'package:crm/domain/entities/entities.dart';

class CreateOrderInput {
  const CreateOrderInput({
    required this.clientId,
    required this.clientName,
    required this.items,
    required this.paymentStatus,
    this.comment,
  });

  final String clientId;
  final String clientName;
  final List<OrderItem> items;
  final PaymentStatus paymentStatus;
  final String? comment;
}

abstract class ProductRepository {
  Future<List<Product>> getProducts();
  Future<List<Product>> getLowStockProducts();
}

abstract class ClientRepository {
  Future<List<Client>> getClients();
  Future<Client> createClient({required String name, required String phone, String? comment});
}

abstract class OrderRepository {
  Future<List<Order>> getOrders();
  Future<Order?> getOrderById(String id);
  Future<Order> createOrder(CreateOrderInput input);
  Future<Order?> updatePaymentStatus(String orderId, PaymentStatus status);
}

abstract class DashboardRepository {
  Future<DashboardStats> getDashboardStats();
}
