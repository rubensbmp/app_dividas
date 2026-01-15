import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart'; // Importação do serviço de notificação

// --- CONTROLE GLOBAL DE TEMA ---
// Essas variáveis (ValueNotifier) permitem que qualquer tela mude a cor ou o modo (Claro/Escuro)
// e o aplicativo inteiro reaja instantaneamente sem precisar reiniciar.
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.light);
final ValueNotifier<Color> colorNotifier = ValueNotifier(Colors.blue);

void main() async {
  // Garante que a estrutura do Flutter esteja pronta antes de rodar códigos nativos
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa o sistema de notificações (pede permissão, configura ícone, etc)
  await NotificationService().init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. Ouve mudanças na COR escolhida pelo usuário
    return ValueListenableBuilder<Color>(
      valueListenable: colorNotifier,
      builder: (_, color, __) {

        // 2. Ouve mudanças no MODO (Claro ou Escuro)
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeNotifier,
          builder: (_, mode, __) {

            return MaterialApp(
              debugShowCheckedModeBanner: false, // Remove a faixa "DEBUG" do canto
              title: 'Controle de Dívidas',
              themeMode: mode, // Aplica o modo escolhido (Light/Dark/System)

              // --- TEMA CLARO (LIGHT) ---
              theme: ThemeData(
                brightness: Brightness.light,
                primaryColor: color,
                // Gera todas as cores secundárias baseadas na cor principal
                colorScheme: ColorScheme.fromSeed(seedColor: color, brightness: Brightness.light),
                scaffoldBackgroundColor: const Color(0xFFF0F4F8), // Fundo cinza bem suave
                useMaterial3: true,
                // Estilo da Barra Superior
                appBarTheme: AppBarTheme(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  centerTitle: true,
                  elevation: 2,
                ),
                // Estilo dos Botões Flutuantes (+ e Add Pessoa)
                floatingActionButtonTheme: FloatingActionButtonThemeData(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                ),
                // Estilo dos Botões Elevados (Salvar, Gerar, etc)
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
                scaffoldBackgroundColor: const Color(0xFF121212), // Fundo preto suave (padrão Material)
                useMaterial3: true,
                // Barra Superior no modo escuro fica cinza chumbo
                appBarTheme: AppBarTheme(
                  backgroundColor: const Color(0xFF1E1E1E),
                  foregroundColor: Colors.white,
                  centerTitle: true,
                  elevation: 0,
                ),

                // Configurações de Cards e Caixas de Diálogo para cinza escuro
                // IMPORTANTE: Usando 'CardThemeData' para compatibilidade com Flutter novo
                cardTheme: const CardThemeData(
                  color: Color(0xFF1E1E1E),
                ),
                dialogTheme: const DialogThemeData(
                  backgroundColor: Color(0xFF2C2C2C),
                ),

                // Botões flutuantes no escuro usam ícone preto para contraste com a cor viva
                floatingActionButtonTheme: FloatingActionButtonThemeData(
                  backgroundColor: color,
                  foregroundColor: Colors.black,
                ),
              ),

              // --- CONFIGURAÇÃO DE IDIOMA (PT-BR) ---
              // Isso garante que o calendário, formatação de moeda e textos padrões (Copiar/Colar)
              // estejam em Português do Brasil.
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('pt', 'BR')],

              // Define a tela inicial do aplicativo
              home: HomeScreen(),
            );
          },
        );
      },
    );
  }
}