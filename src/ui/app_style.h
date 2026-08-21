#ifndef CHARTINSPECTOR_UI_APP_STYLE_H
#define CHARTINSPECTOR_UI_APP_STYLE_H

#include <wx/colour.h>
#include <wx/font.h>

#include "ocpn_plugin.h"

namespace ci_ui {

struct AppPalette {
  wxColour windowBackground;
  wxColour cardBackground;
  wxColour cardBorder;
  wxColour textPrimary;
  wxColour textSecondary;
  wxColour accent;
};

class AppStyle {
public:
  static const int kSpaceXs = 4;
  static const int kSpaceSm = 8;
  static const int kSpaceMd = 12;
  static const int kSpaceLg = 16;
  static const int kSpaceXl = 24;
  static const int kCardRadius = 10;
  static const int kCardPadding = 12;
  static const int kLabelColumnWidth = 112;
  static const int kColorChipSize = 16;

  static AppPalette PaletteFor(PI_ColorScheme scheme);
  static wxFont TitleFont(const wxFont &base);
  static wxFont PrimaryFont(const wxFont &base);
  static wxFont LabelFont(const wxFont &base);
  static wxFont TechnicalFont(const wxFont &base);
};

}  // namespace ci_ui

#endif
