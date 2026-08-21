#include "ui/app_style.h"

#include <algorithm>

#include <wx/settings.h>

namespace ci_ui {
namespace {

wxColour Blend(const wxColour &a, const wxColour &b, double amountB) {
  amountB = std::max(0.0, std::min(1.0, amountB));
  const double amountA = 1.0 - amountB;
  return wxColour(
      static_cast<unsigned char>(a.Red() * amountA + b.Red() * amountB),
      static_cast<unsigned char>(a.Green() * amountA + b.Green() * amountB),
      static_cast<unsigned char>(a.Blue() * amountA + b.Blue() * amountB));
}

}  // namespace

AppPalette AppStyle::PaletteFor(PI_ColorScheme scheme) {
  AppPalette p;
  p.windowBackground = wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOW);
  p.textPrimary = wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOWTEXT);
  p.textSecondary = wxSystemSettings::GetColour(wxSYS_COLOUR_GRAYTEXT);

  GetGlobalColor("DILG0", &p.windowBackground);
  GetGlobalColor("DILG4", &p.textPrimary);
  GetGlobalColor("DILG3", &p.textSecondary);

  const bool dark = scheme == PI_GLOBAL_COLOR_SCHEME_DUSK ||
                    scheme == PI_GLOBAL_COLOR_SCHEME_NIGHT;
  const wxColour white(255, 255, 255);
  p.cardBackground = Blend(p.windowBackground, white, dark ? 0.08 : 0.48);
  p.cardBorder = Blend(p.windowBackground, p.textPrimary, dark ? 0.20 : 0.12);
  p.textSecondary = Blend(p.windowBackground, p.textPrimary, dark ? 0.70 : 0.55);

  p.accent = wxColour(0, 205, 225);
  if (scheme == PI_GLOBAL_COLOR_SCHEME_DUSK)
    p.accent = wxColour(0, 165, 185);
  else if (scheme == PI_GLOBAL_COLOR_SCHEME_NIGHT)
    p.accent = wxColour(0, 120, 140);
  return p;
}

wxFont AppStyle::TitleFont(const wxFont &base) {
  wxFont f = base;
  f.SetWeight(wxFONTWEIGHT_BOLD);
  f.SetPointSize(f.GetPointSize() + 2);
  return f;
}

wxFont AppStyle::PrimaryFont(const wxFont &base) {
  wxFont f = base;
  f.SetWeight(wxFONTWEIGHT_BOLD);
  f.SetPointSize(f.GetPointSize() + 1);
  return f;
}

wxFont AppStyle::LabelFont(const wxFont &base) {
  wxFont f = base;
  f.SetWeight(wxFONTWEIGHT_NORMAL);
  return f;
}

wxFont AppStyle::TechnicalFont(const wxFont &base) {
  wxFont f = base;
  f.SetPointSize(std::max(7, f.GetPointSize() - 1));
  return f;
}

}  // namespace ci_ui
