import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String url = "https://muefvrvzobbafgppqdcf.supabase.co";
  static const String anonKey =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im11ZWZ2cnZ6b2JiYWZncHBxZGNmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM1NDE1OTMsImV4cCI6MjA3OTExNzU5M30.CQHDxPDwBSWA1bUHGk6CcafyHpy6WRGht2uBcO9KI14";

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  }
}
