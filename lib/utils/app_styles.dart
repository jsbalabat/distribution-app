// lib/utils/app_styles.dart
import 'package:flutter/material.dart';

class AppStyles {
  // Primary colors
  static const Color primaryColor = Color(0xFF6A1B9A); // Deep Purple
  static const Color secondaryColor = Color(0xFF9C27B0); // Purple
  static const Color accentColor = Color(0xFFE1BEE7); // Light Purple

  // Background colors
  static const Color backgroundColor = Color(0xFFF5F5F5);
  static const Color cardColor = Color(0xFFFFFFFF);
  static const Color scaffoldBackgroundColor = Color(0xFFFAFAFA);

  // Text colors
  static const Color textColor = Color(0xFF212121);
  static const Color textSecondaryColor = Color(0xFF757575);
  static const Color textLightColor = Color(0xFF9E9E9E);

  // Status colors
  static const Color successColor = Color(0xFF4CAF50);
  static const Color warningColor = Color(0xFFFFC107);
  static const Color errorColor = Color(0xFFF44336);
  static const Color infoColor = Color(0xFF2196F3);

  // Common elevation
  static const double cardElevation = 2.0;
  static const double modalElevation = 4.0;

  // Text styles
  static const TextStyle headingStyle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: textColor,
  );

  static const TextStyle subheadingStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: textColor,
  );

  static const TextStyle titleStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: textColor,
  );

  static const TextStyle bodyStyle = TextStyle(fontSize: 16, color: textColor);

  static const TextStyle captionStyle = TextStyle(
    fontSize: 14,
    color: textSecondaryColor,
  );

  static const TextStyle buttonTextStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  // Button styles
  static final ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: primaryColor,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    elevation: 2,
  );

  static final ButtonStyle secondaryButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: primaryColor,
    side: const BorderSide(color: primaryColor),
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );

  static final ButtonStyle textButtonStyle = TextButton.styleFrom(
    foregroundColor: primaryColor,
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
  );

  // Card styles
  static final BoxDecoration cardDecoration = BoxDecoration(
    color: cardColor,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        spreadRadius: 1,
        blurRadius: 5,
        offset: const Offset(0, 2),
      ),
    ],
  );

  // Input decoration
  static const InputDecoration inputDecoration = InputDecoration(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
      borderSide: BorderSide(color: Color(0xFFDDDDDD)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
      borderSide: BorderSide(color: Color(0xFFDDDDDD)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
      borderSide: BorderSide(color: primaryColor, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
      borderSide: BorderSide(color: errorColor),
    ),
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  );

  // Status badge styles
  static BoxDecoration statusBadgeDecoration(Color color) {
    return BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color, width: 1),
    );
  }

  // Padding values
  static const EdgeInsets screenPadding = EdgeInsets.all(16.0);
  static const EdgeInsets cardPadding = EdgeInsets.all(16.0);
  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(
    vertical: 12.0,
    horizontal: 16.0,
  );
  static const EdgeInsets sectionPadding = EdgeInsets.symmetric(vertical: 24.0);

  // Spacing values
  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 16.0;
  static const double spacingL = 24.0;
  static const double spacingXL = 32.0;
  static const double spacingXXL = 48.0;

  // Border radius
  static const double borderRadiusSmall = 4.0;
  static const double borderRadiusMedium = 8.0;
  static const double borderRadiusLarge = 12.0;
  static const double borderRadiusXLarge = 24.0;

  // Admin dashboard specific styles
  static const Color adminPrimaryColor = Color(
    0xFF1A237E,
  ); // Darker blue for admin
  static final BoxDecoration adminCardDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        spreadRadius: 1,
        blurRadius: 5,
        offset: const Offset(0, 2),
      ),
    ],
  );

  // Stat card gradient backgrounds
  static const List<List<Color>> statCardGradients = [
    [Color(0xFF1A237E), Color(0xFF3949AB)], // Blue
    [Color(0xFF1B5E20), Color(0xFF388E3C)], // Green
    [Color(0xFFE65100), Color(0xFFF57C00)], // Orange
    [Color(0xFF4A148C), Color(0xFF7B1FA2)], // Purple
  ];

  // Animation durations
  static const Duration shortAnimationDuration = Duration(milliseconds: 200);
  static const Duration mediumAnimationDuration = Duration(milliseconds: 350);
  static const Duration longAnimationDuration = Duration(milliseconds: 500);
}
