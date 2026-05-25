import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

final languageProvider = StateNotifierProvider<LanguageNotifier, Locale>((ref) {
  return LanguageNotifier();
});

class LanguageNotifier extends StateNotifier<Locale> {
  LanguageNotifier() : super(const Locale('en')) {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final languageCode = prefs.getString('language_code') ?? 'en';
      state = Locale(languageCode);
    } catch (e) {
      // ignore: avoid_print
      print('Error loading language: $e');
      state = const Locale('en');
    }
  }

  Future<void> setLanguage(String languageCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language_code', languageCode);
      state = Locale(languageCode);
    } catch (e) {
      // ignore: avoid_print
      print('Error setting language: $e');
    }
  }

  String getCurrentLanguageCode() => state.languageCode;
  bool isAmharic() => state.languageCode == 'am';
  bool isEnglish() => state.languageCode == 'en';
}