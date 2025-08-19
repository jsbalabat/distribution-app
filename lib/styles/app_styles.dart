import 'package:flutter/material.dart';

/// Application-wide style definitions
class AppStyles {
  // Color scheme
  static const Color primaryColor = Color(0xFF5E4BA6);
  static const Color secondaryColor = Color(0xFFE55986);
  static const Color backgroundColor = Color(0xFFF2EDFF);
  static const Color cardColor = Colors.white;
  static const Color textColor = Color(0xFF333333);
  static const Color subtitleColor = Color(0xFF666666);

  // Font sizes
  static const double fontSizeSmall = 12.0;
  static const double fontSizeNormal = 14.0;
  static const double fontSizeMedium = 16.0;
  static const double fontSizeLarge = 18.0;
  static const double fontSizeXLarge = 24.0;

  // Border radius values
  static const double borderRadiusSmall = 8.0;
  static const double borderRadiusMedium = 12.0;
  static const double borderRadiusLarge = 16.0;

  // Padding values
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;

  // Card elevation
  static const double cardElevationSmall = 1.0;
  static const double cardElevationNormal = 2.0;

  // Text styles
  static const TextStyle titleStyle = TextStyle(
    fontSize: fontSizeLarge,
    fontWeight: FontWeight.bold,
    color: textColor,
  );

  static const TextStyle subtitleStyle = TextStyle(
    fontSize: fontSizeNormal,
    color: subtitleColor,
  );

  static const TextStyle appBarTitleStyle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.bold,
  );

  // Button styles
  static final ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: primaryColor,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadiusMedium),
    ),
  );

  static final ButtonStyle secondaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: secondaryColor,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadiusMedium),
    ),
  );

  static final ButtonStyle outlineButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: primaryColor,
    side: const BorderSide(color: primaryColor),
    padding: const EdgeInsets.symmetric(vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadiusMedium),
    ),
  );

  // Input decoration
  static InputDecoration inputDecoration({
    required String hintText,
    IconData? prefixIcon,
    String? errorText,
  }) {
    return InputDecoration(
      hintText: hintText,
      errorText: errorText,
      filled: true,
      fillColor: Colors.grey[100],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusMedium),
        borderSide: BorderSide.none,
      ),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: primaryColor)
          : null,
      errorStyle: const TextStyle(color: secondaryColor),
    );
  }
}
