import 'package:crm/features/pages.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (_, state) => _buildPage(
          state: state,
          child: const LoginPage(),
        ),
      ),
      GoRoute(
        path: '/dashboard',
        pageBuilder: (_, state) => _buildPage(
          state: state,
          child: const ShellScaffold(index: 0, child: DashboardPage()),
        ),
      ),
      GoRoute(
        path: '/products',
        pageBuilder: (_, state) => _buildPage(
          state: state,
          child: const ShellScaffold(index: 1, child: ProductsPage()),
        ),
      ),
      GoRoute(
        path: '/orders',
        pageBuilder: (_, state) => _buildPage(
          state: state,
          child: const ShellScaffold(index: 2, child: OrdersPage()),
        ),
      ),
      GoRoute(
        path: '/clients',
        pageBuilder: (_, state) => _buildPage(
          state: state,
          child: const ShellScaffold(index: 3, child: ClientsPage()),
        ),
      ),
      GoRoute(
        path: '/stock',
        pageBuilder: (_, state) => _buildPage(
          state: state,
          child: const ShellScaffold(index: 4, child: StockPage()),
        ),
      ),
      GoRoute(
        path: '/create-order',
        pageBuilder: (_, state) => _buildPage(
          state: state,
          child: const CreateOrderPage(),
          beginOffset: const Offset(0, 0.08),
        ),
      ),
      GoRoute(
        path: '/order/:id',
        pageBuilder: (_, state) => _buildPage(
          state: state,
          child: OrderDetailsPage(id: state.pathParameters['id']!),
          beginOffset: const Offset(0.08, 0),
        ),
      ),
    ],
  );
}

CustomTransitionPage<void> _buildPage({
  required GoRouterState state,
  required Widget child,
  Offset beginOffset = const Offset(0.03, 0),
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: beginOffset,
            end: Offset.zero,
          ).animate(curve),
          child: child,
        ),
      );
    },
  );
}
