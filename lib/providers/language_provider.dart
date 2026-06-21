import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:caddymoney/core/constants/app_constants.dart';

class LanguageProvider with ChangeNotifier {
  Locale _currentLocale = const Locale('fr');
  
  Locale get currentLocale => _currentLocale;
  String get languageCode => _currentLocale.languageCode;

  LanguageProvider() {
    _loadSavedLanguage();
  }

  Future<void> _loadSavedLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLanguage = prefs.getString('language_code') ?? AppConstants.defaultLanguage;
      _currentLocale = Locale(savedLanguage);
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading language: $e');
    }
  }

  Future<void> setLanguage(String languageCode) async {
    if (!AppConstants.supportedLanguages.contains(languageCode)) return;
    
    _currentLocale = Locale(languageCode);
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language_code', languageCode);
    } catch (e) {
      debugPrint('Error saving language: $e');
    }
  }
}
