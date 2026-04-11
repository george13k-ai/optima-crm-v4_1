import 'package:crm/data/mock_backend.dart';
import 'package:crm/domain/entities/entities.dart';
import 'package:crm/features/cubits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrderDraftCubit', () {
    late MockBackend backend;
    late OrderDraftCubit cubit;
    late Product product;
    late Client client;

    setUp(() async {
      backend = MockBackend();
      cubit = OrderDraftCubit(backend);
      product = (await backend.getProducts()).firstWhere((p) => p.id == 'p2');
      client = (await backend.getClients()).first;
    });

    test('keeps current draft data when client is missing', () async {
      cubit.addProduct(product);
      cubit.setComment('Urgent');

      final created = await cubit.createOrder();

      expect(created, isNull);
      expect(cubit.state.lines, isNotEmpty);
      expect(cubit.state.comment, 'Urgent');
      expect(cubit.state.error, 'Выберите клиента.');
    });

    test('does not allow quantity above stock', () {
      cubit.addProduct(product);
      cubit.setQty(product.id, product.stock + 1);

      expect(cubit.state.lines.single.quantity, 1);
      expect(cubit.state.error, 'На складе доступно только ${product.stock} шт.');
    });

    test('creates order when draft is valid', () async {
      cubit.addProduct(product);
      cubit.pickClient(client);
      cubit.setPayment(PaymentStatus.paid);

      final created = await cubit.createOrder();

      expect(created, isNotNull);
      expect(created!.clientId, client.id);
      expect(created.paymentStatus, PaymentStatus.paid);
      expect(created.items.single.quantity, 1);
    });

    test('imports google sheets rows into the draft', () async {
      final products = await backend.getProducts();
      final clients = await backend.getClients();

      final message = cubit.importTableText(
        raw: 'Client\tProduct\tQty\tPayment\n'
            'Tech Store\tGalaxy S24\t1\tPaid\n'
            'Tech Store\tSKU-004\t2\tPaid',
        products: products,
        clients: clients,
      );

      expect(message, contains('импортировано 2 позиций'));
      expect(cubit.state.client?.name, 'Tech Store');
      expect(cubit.state.paymentStatus, PaymentStatus.paid);
      expect(cubit.state.lines.length, 2);
      expect(cubit.state.lines.first.product.id, 'p2');
    });
  });
}
