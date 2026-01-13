import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/home_screen.dart';

// --- CONTROLE GLOBAL DE TEMA ---
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.light);
final ValueNotifier<Color> colorNotifier = ValueNotifier(Colors.blue);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: colorNotifier,
      builder: (_, color, __) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeNotifier,
          builder: (_, mode, __) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'Controle de Dívidas',
              themeMode: mode,

              // --- TEMA CLARO ---
              theme: ThemeData(
                brightness: Brightness.light,
                primaryColor: color,
                colorScheme: ColorScheme.fromSeed(seedColor: color, brightness: Brightness.light),
                scaffoldBackgroundColor: const Color(0xFFF0F4F8),
                useMaterial3: true,
                appBarTheme: AppBarTheme(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  centerTitle: true,
                  elevation: 2,
                ),
                floatingActionButtonTheme: FloatingActionButtonThemeData(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),

              // --- TEMA ESCURO (DARK MODE) ---
              darkTheme: ThemeData(
                brightness: Brightness.dark,
                primaryColor: color,
                colorScheme: ColorScheme.fromSeed(seedColor: color, brightness: Brightness.dark),
                scaffoldBackgroundColor: const Color(0xFF121212),
                useMaterial3: true,
                appBarTheme: AppBarTheme(
                  backgroundColor: const Color(0xFF1E1E1E),
                  foregroundColor: Colors.white,
                  centerTitle: true,
                  elevation: 0,
                ),

                // CORREÇÃO AQUI: Mudamos CardTheme para CardThemeData (ou removemos se continuar dando erro)
                cardTheme: const CardThemeData(
                  color: Color(0xFF1E1E1E),
                ),

                // CORREÇÃO AQUI: Mudamos DialogTheme para DialogThemeData
                dialogTheme: const DialogThemeData(
                  backgroundColor: Color(0xFF2C2C2C),
                ),

                floatingActionButtonTheme: FloatingActionButtonThemeData(
                  backgroundColor: color,
                  foregroundColor: Colors.black,
                ),
              ),

              // Configuração para datas e moeda em Português
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('pt', 'BR')],

              home: HomeScreen(),
            );
          },
        );
      },
    );
  }
}