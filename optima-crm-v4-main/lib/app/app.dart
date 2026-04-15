import 'package:crm/app/router.dart';
import 'package:crm/data/mock_backend.dart';
import 'package:crm/features/cubits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class CrmApp extends StatefulWidget {
  const CrmApp({super.key, required this.mock});

  final MockBackend mock;

  @override
  State<CrmApp> createState() => _CrmAppState();
}

class _CrmAppState extends State<CrmApp> {
  late final router = buildRouter();

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFEF7C45);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xFF141A23),
      surfaceContainerHighest: const Color(0xFF1A2230),
      primary: const Color(0xFFF18B54),
      secondary: const Color(0xFF6EC6CA),
    );

    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ProductsCubit(widget.mock)..load()),
        BlocProvider(create: (_) => ClientsCubit(widget.mock)..load()),
        BlocProvider(create: (_) => OrdersCubit(widget.mock)..load()),
        BlocProvider(create: (_) => StockCubit(widget.mock)..load()),
        BlocProvider(create: (_) => DashboardCubit(widget.mock)..load()),
        BlocProvider(create: (_) => OrderDraftCubit(widget.mock)),
      ],
      child: MaterialApp.router(
        title: 'Оптима CRM',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ru', 'RU'),
        supportedLocales: const [
          Locale('ru', 'RU'),
          Locale('en', 'US'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          scaffoldBackgroundColor: const Color(0xFF09111A),
          textTheme: ThemeData.dark().textTheme.apply(
                bodyColor: const Color(0xFFF3F2EF),
                displayColor: const Color(0xFFF3F2EF),
              ),
          cardTheme: CardThemeData(
            color: const Color(0xFF121A24).withValues(alpha: 0.86),
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: false,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF18B54),
              foregroundColor: const Color(0xFF10151D),
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF121C28).withValues(alpha: 0.85),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFF18B54)),
            ),
          ),
          snackBarTheme: SnackBarThemeData(
            backgroundColor: const Color(0xFF121A24),
            contentTextStyle: const TextStyle(color: Colors.white),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: Colors.transparent,
            indicatorColor: const Color(0xFFF18B54).withValues(alpha: 0.2),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                color: states.contains(WidgetState.selected)
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.7),
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
          dividerColor: Colors.white.withValues(alpha: 0.08),
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
              TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
              TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
            },
          ),
        ),
        routerConfig: router,
      ),
    );
  }
}
