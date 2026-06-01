import 'package:flutter/material.dart';

class MoaDesignTokens {
  const MoaDesignTokens._();

  static const Color background = Color(0xFFF5F8FB);
  static const Color surface = Color(0xEFFFFFFF);
  static const Color surfaceSolid = Color(0xFFF8FBFE);
  static const Color surfaceAlt = Color(0xFFEAF2F8);
  static const Color stroke = Color(0xFFE2ECF3);
  static const Color accent = Color(0xFF59D5FF);
  static const Color accentStrong = Color(0xFF38BDF8);
  static const Color accentSoft = Color(0xFFB9F3FF);
  static const Color textPrimary = Color(0xFF071018);
  static const Color textMuted = Color(0xFF647386);
  static const Color textFaint = Color(0xFF8CA0B3);
  static const Color success = Color(0xFF0F9F73);
  static const Color successSoft = Color(0xFFE8FFF6);
  static const Color warning = Color(0xFFFFB86C);
  static const Color warningSoft = Color(0xFFFFF4E4);
  static const Color danger = Color(0xFFFF5C7A);
  static const Color dangerSoft = Color(0xFFFFEEF2);
  static const Color mediaOverlay = Color(0xA6121A24);
  static const Color mediaOverlayStroke = Color(0x33FFFFFF);
  static const Color modalBarrier = Color(0x66000000);

  static const double radiusXl = 28.0;
  static const double radiusLg = 24.0;
  static const double radiusMd = 18.0;
  static const double radiusSm = 12.0;

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF67E8F9), Color(0xFF38BDF8)],
  );

  static const List<BoxShadow> cardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x14214155), blurRadius: 18, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> panelShadow = <BoxShadow>[
    BoxShadow(color: Color(0x1A214155), blurRadius: 22, offset: Offset(0, 10)),
  ];

  static const List<BoxShadow> activeGlow = <BoxShadow>[
    BoxShadow(color: Color(0x3359D5FF), blurRadius: 18, offset: Offset(0, 7)),
  ];

  static const List<BoxShadow> mediaOverlayShadow = <BoxShadow>[
    BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8)),
  ];
}
