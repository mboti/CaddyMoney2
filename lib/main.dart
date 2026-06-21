import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:caddymoney/core/utils/app_localizations_temp.dart';
import 'package:caddymoney/theme.dart';
import 'package:caddymoney/nav.dart';
import 'package:caddymoney/providers/auth_provider.dart';
import 'package:caddymoney/providers/language_provider.dart';
import 'package:caddymoney/core/config/supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseConfig.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: Consumer<LanguageProvider>(
        builder: (context, languageProvider, _) {
          return MaterialApp.router(
            title: 'CaddyMoney',
            debugShowCheckedModeBanner: false,
            
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: ThemeMode.system,
            
            locale: languageProvider.currentLocale,
            supportedLocales: const [
              Locale('fr'),
              Locale('en'),
              Locale('es'),
              Locale('de'),
              Locale('it'),
              Locale('ar'),
            ],
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            
            routerConfig: AppRouter.router,
          );
        },
      ),
    );
  }
}
