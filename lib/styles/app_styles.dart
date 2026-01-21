import 'package:flutter/material.dart';

class AppStyles {
  // Modern Black and White Color Palette with Hues
  static const Color primaryColor = Color(0xFF000000); // Pure Black
  static const Color secondaryColor = Color(0xFF1A1A1A); // Dark Charcoal
  static const Color accentColor = Color(0xFF2D2D2D); // Medium Charcoal
  static const Color backgroundColor = Color(0xFFF5F5F5); // Off White
  static const Color cardColor = Color(0xFFFFFFFF); // Pure White
  static const Color scaffoldBackgroundColor = Color(0xFFFAFAFA); // Light Gray
  static const Color textColor = Color(0xFF0A0A0A); // Near Black
  static const Color subtitleColor = Color(0xFF4A4A4A); // Dark Gray
  static const Color textSecondaryColor = Color(0xFF6B6B6B); // Medium Gray
  static const Color textLightColor = Color(0xFF9E9E9E); // Light Gray

  // Status Colors - Modern Monochrome Variants
  static const Color successColor = Color(0xFF2C2C2C); // Dark Gray (Success)
  static const Color warningColor = Color(0xFF555555); // Medium Gray (Warning)
  static const Color errorColor = Color(0xFF1A1A1A); // Charcoal (Error)
  static const Color infoColor = Color(0xFF3D3D3D); // Slate Gray (Info)
  static const Color adminPrimaryColor = Color(
    0xFF000000,
  ); // Pure Black (Admin)

  static const double fontSizeSmall = 12.0;
  static const double fontSizeNormal = 14.0;
  static const double fontSizeMedium = 16.0;
  static const double fontSizeLarge = 18.0;
  static const double fontSizeXLarge = 24.0;

  static const double borderRadiusSmall = 4.0;
  static const double borderRadiusMedium = 8.0;
  static const double borderRadiusLarge = 12.0;
  static const double borderRadiusXLarge = 24.0;

  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;

  static const double cardElevation = 2.0;
  static const double cardElevationSmall = 1.0;
  static const double cardElevationNormal = 2.0;
  static const double modalElevation = 4.0;

  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 16.0;
  static const double spacingL = 24.0;
  static const double spacingXL = 32.0;
  static const double spacingXXL = 48.0;

  static const EdgeInsets screenPadding = EdgeInsets.all(16.0);
  static const EdgeInsets cardPadding = EdgeInsets.all(16.0);
  static const EdgeInsets listItemPadding = EdgeInsets.symmetric(
    vertical: 12.0,
    horizontal: 16.0,
  );
  static const EdgeInsets sectionPadding = EdgeInsets.symmetric(vertical: 24.0);

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
    fontSize: fontSizeLarge,
    fontWeight: FontWeight.w600,
    color: textColor,
  );

  static const TextStyle bodyStyle = TextStyle(
    fontSize: fontSizeMedium,
    color: textColor,
  );

  static const TextStyle subtitleStyle = TextStyle(
    fontSize: fontSizeNormal,
    color: subtitleColor,
  );

  static const TextStyle captionStyle = TextStyle(
    fontSize: fontSizeNormal,
    color: textSecondaryColor,
  );

  static const TextStyle buttonTextStyle = TextStyle(
    fontSize: fontSizeMedium,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  static const TextStyle appBarTitleStyle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.bold,
  );

  static final ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: primaryColor,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadiusMedium),
    ),
    elevation: 2,
  );

  static final ButtonStyle secondaryButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: primaryColor,
    side: const BorderSide(color: primaryColor),
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadiusMedium),
    ),
  );

  static final ButtonStyle textButtonStyle = TextButton.styleFrom(
    foregroundColor: primaryColor,
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
  );

  static final ButtonStyle outlineButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: primaryColor,
    side: const BorderSide(color: primaryColor),
    padding: const EdgeInsets.symmetric(vertical: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadiusMedium),
    ),
  );

  static final BoxDecoration cardDecoration = BoxDecoration(
    color: cardColor,
    borderRadius: BorderRadius.circular(borderRadiusLarge),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.08),
        spreadRadius: 0,
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        spreadRadius: 0,
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
    ],
  );

  static final BoxDecoration adminCardDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(borderRadiusLarge),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.08),
        spreadRadius: 0,
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        spreadRadius: 0,
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
    ],
  );

  static BoxDecoration statusBadgeDecoration(Color color) {
    return BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(borderRadiusLarge),
      border: Border.all(color: color, width: 1),
    );
  }

  static const List<List<Color>> statCardGradients = [
    [Color(0xFF000000), Color(0xFF2D2D2D)], // Black to Charcoal
    [Color(0xFF1A1A1A), Color(0xFF3D3D3D)], // Dark Charcoal to Slate
    [Color(0xFF2D2D2D), Color(0xFF4A4A4A)], // Charcoal to Dark Gray
    [Color(0xFF0A0A0A), Color(0xFF262626)], // Near Black to Dark
  ];

  static const Duration shortAnimationDuration = Duration(milliseconds: 200);
  static const Duration mediumAnimationDuration = Duration(milliseconds: 350);
  static const Duration longAnimationDuration = Duration(milliseconds: 500);

  static const InputDecoration inputDecoration = InputDecoration(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(borderRadiusMedium)),
      borderSide: BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(borderRadiusMedium)),
      borderSide: BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(borderRadiusMedium)),
      borderSide: BorderSide(color: primaryColor, width: 2.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(borderRadiusMedium)),
      borderSide: BorderSide(color: Color(0xFF1A1A1A), width: 1.5),
    ),
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  );

  static InputDecoration inputDecorationWithHint({
    required String hintText,
    IconData? prefixIcon,
    String? errorText,
  }) {
    return InputDecoration(
      hintText: hintText,
      errorText: errorText,
      filled: true,
      fillColor: Color(0xFFFAFAFA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusMedium),
        borderSide: BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusMedium),
        borderSide: BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusMedium),
        borderSide: BorderSide(color: primaryColor, width: 2.5),
      ),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: primaryColor)
          : null,
      errorStyle: const TextStyle(color: Color(0xFF1A1A1A)),
    );
  }
}
