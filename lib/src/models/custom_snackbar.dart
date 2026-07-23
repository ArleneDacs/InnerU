import 'package:flutter/material.dart';

class CustomSnackBar {
  static void showCustomSnackBar(
      BuildContext context, String message, Color bgColor) {
    if (!context.mounted) return; // Ensure context is still valid

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(message, style: TextStyle(color: Colors.black)), // Text color
        backgroundColor: bgColor, // Dynamic background color
        behavior: SnackBarBehavior.floating, // Optional: Floating style
      ),
    );
  }
}
