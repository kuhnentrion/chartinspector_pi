set(ROOT "${CMAKE_CURRENT_LIST_DIR}/..")
set(HDR "${ROOT}/src/chartinspector_pi.h")
set(CPP "${ROOT}/src/chartinspector_pi.cpp")
set(CMAKE_FILE "${ROOT}/CMakeLists.txt")
set(UI_DIR "${ROOT}/src/ui")

foreach(P "${HDR}" "${CPP}" "${CMAKE_FILE}")
  if(NOT EXISTS "${P}")
    message(FATAL_ERROR "Missing ${P}")
  endif()
endforeach()

file(READ "${HDR}" H)
file(READ "${CPP}" C)
file(READ "${CMAKE_FILE}" M)

if(C MATCHES "CHARTINSPECTOR_APPSTYLE_V2")
  message(STATUS "Chart Inspector AppStyle v2 already installed")
  return()
endif()
if(NOT C MATCHES "CHARTINSPECTOR_PROPERTY_GRID_V1")
  message(FATAL_ERROR "Property grid v1 must be installed first")
endif()

# v1 could fail after creating these files/CMake entries but before touching the
# inspector sources. Always overwrite the reusable UI files with the canonical
# v2 versions, and add CMake entries only when missing.
file(MAKE_DIRECTORY "${UI_DIR}")

file(WRITE "${UI_DIR}/app_style.h" [===[
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
  static const int kCardRadius = 8;
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
]===])

file(WRITE "${UI_DIR}/app_style.cpp" [===[
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
  p.cardBackground = Blend(p.windowBackground, white, dark ? 0.10 : 0.72);
  p.cardBorder = Blend(p.windowBackground, p.textPrimary, dark ? 0.26 : 0.18);

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
  f.SetWeight(wxFONTWEIGHT_BOLD);
  return f;
}

wxFont AppStyle::TechnicalFont(const wxFont &base) {
  wxFont f = base;
  f.SetPointSize(std::max(7, f.GetPointSize() - 1));
  return f;
}

}  // namespace ci_ui
]===])

file(WRITE "${UI_DIR}/rounded_panel.h" [===[
#ifndef CHARTINSPECTOR_UI_ROUNDED_PANEL_H
#define CHARTINSPECTOR_UI_ROUNDED_PANEL_H

#include <wx/panel.h>

namespace ci_ui {

class RoundedPanel : public wxPanel {
public:
  RoundedPanel(wxWindow *parent, int radius = 8);
  void SetCardColours(const wxColour &background, const wxColour &border);
  void SetRadius(int radius);

private:
  void OnPaint(wxPaintEvent &event);

  wxColour m_fill;
  wxColour m_border;
  int m_radius = 8;
};

}  // namespace ci_ui

#endif
]===])

file(WRITE "${UI_DIR}/rounded_panel.cpp" [===[
#include "ui/rounded_panel.h"

#include <wx/dcbuffer.h>
#include <wx/settings.h>

namespace ci_ui {

RoundedPanel::RoundedPanel(wxWindow *parent, int radius)
    : wxPanel(parent, wxID_ANY, wxDefaultPosition, wxDefaultSize, wxBORDER_NONE),
      m_fill(wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOW)),
      m_border(wxSystemSettings::GetColour(wxSYS_COLOUR_BTNSHADOW)),
      m_radius(radius) {
  SetBackgroundStyle(wxBG_STYLE_PAINT);
  Bind(wxEVT_PAINT, &RoundedPanel::OnPaint, this);
}

void RoundedPanel::SetCardColours(const wxColour &background,
                                  const wxColour &border) {
  m_fill = background;
  m_border = border;
  SetBackgroundColour(background);
  Refresh(false);
}

void RoundedPanel::SetRadius(int radius) {
  m_radius = radius;
  Refresh(false);
}

void RoundedPanel::OnPaint(wxPaintEvent &) {
  wxAutoBufferedPaintDC dc(this);
  dc.SetBackground(wxBrush(GetParent()->GetBackgroundColour()));
  dc.Clear();
  const wxSize size = GetClientSize();
  if (size.x <= 1 || size.y <= 1) return;
  dc.SetPen(wxPen(m_border, 1));
  dc.SetBrush(wxBrush(m_fill));
  dc.DrawRoundedRectangle(0, 0, size.x - 1, size.y - 1, m_radius);
}

}  // namespace ci_ui
]===])

if(NOT M MATCHES "src/ui/app_style.cpp")
  set(CMAKE_OLD [===[
    src/s57_catalog.cpp
    src/s57_catalog.h
)
]===])
  set(CMAKE_NEW [===[
    src/s57_catalog.cpp
    src/s57_catalog.h
    src/ui/app_style.cpp
    src/ui/app_style.h
    src/ui/rounded_panel.cpp
    src/ui/rounded_panel.h
)
]===])
  string(FIND "${M}" "${CMAKE_OLD}" MPOS)
  if(MPOS EQUAL -1)
    message(FATAL_ERROR "Could not locate source list in CMakeLists.txt")
  endif()
  string(REPLACE "${CMAKE_OLD}" "${CMAKE_NEW}" M "${M}")
  file(WRITE "${CMAKE_FILE}" "${M}")
endif()

# Header edits, deliberately anchored to individual symbols instead of a whole
# multi-line declaration. Current source includes the optional associated-light
# parameter added after property-grid v1.
if(NOT H MATCHES "#include <wx/sizer.h>")
  string(REPLACE "#include <wx/string.h>" "#include <wx/string.h>\n#include <wx/sizer.h>" H "${H}")
endif()

if(NOT H MATCHES "void ApplyHoverWindowTheme\(\);")
  set(UPDATE_DECL "  void UpdateHoverInfoPanel(")
  string(FIND "${H}" "${UPDATE_DECL}" DPOS)
  if(DPOS EQUAL -1)
    message(FATAL_ERROR "Could not locate UpdateHoverInfoPanel declaration")
  endif()
  string(SUBSTRING "${H}" 0 ${DPOS} HPRE)
  string(SUBSTRING "${H}" ${DPOS} -1 HPOST)
  set(H "${HPRE}  void ApplyHoverWindowTheme();\n${HPOST}")
endif()

if(NOT H MATCHES "m_hoverInfoGrid")
  set(MEMBER_ANCHOR "  wxPanel *m_hoverInfoDetails = nullptr;\n")
  string(FIND "${H}" "${MEMBER_ANCHOR}" MEMPOS)
  if(MEMPOS EQUAL -1)
    message(FATAL_ERROR "Could not locate m_hoverInfoDetails member")
  endif()
  string(REPLACE "${MEMBER_ANCHOR}"
                 "${MEMBER_ANCHOR}  wxFlexGridSizer *m_hoverInfoGrid = nullptr;\n"
                 H "${H}")
endif()
file(WRITE "${HDR}" "${H}")

if(NOT C MATCHES "ui/app_style.h")
  string(REPLACE "#include \"chartinspector_pi.h\""
                 "#include \"chartinspector_pi.h\"\n#include \"ui/app_style.h\"\n#include \"ui/rounded_panel.h\""
                 C "${C}")
endif()

# Add theme refresh to SetColorScheme if absent.
if(NOT C MATCHES "ApplyInfoTheme\(\);[\r\n ]+ApplyHoverWindowTheme\(\);")
  set(SCHEME_OLD "  ApplyInfoTheme();\n  if (m_infoPanel && m_infoPanel->IsShown()) {")
  set(SCHEME_NEW "  ApplyInfoTheme();\n  ApplyHoverWindowTheme();\n  if (m_infoPanel && m_infoPanel->IsShown()) {")
  string(FIND "${C}" "${SCHEME_OLD}" CSPOS)
  if(CSPOS EQUAL -1)
    message(FATAL_ERROR "Could not locate SetColorScheme theme call")
  endif()
  string(REPLACE "${SCHEME_OLD}" "${SCHEME_NEW}" C "${C}")
endif()

# Property rows use shared typography and a fixed label column.
if(NOT C MATCHES "kLabelColumnWidth")
  set(ROW_LABEL_OLD [===[
  wxStaticText *name = new wxStaticText(panel, wxID_ANY, label);
  wxFont labelFont = name->GetFont();
  labelFont.SetWeight(wxFONTWEIGHT_BOLD);
  name->SetFont(labelFont);
  grid->Add(name, 0, wxALIGN_TOP | wxTOP, 1);
]===])
  set(ROW_LABEL_NEW [===[
  wxStaticText *name = new wxStaticText(panel, wxID_ANY, label);
  name->SetFont(ci_ui::AppStyle::LabelFont(name->GetFont()));
  name->SetMinSize(wxSize(ci_ui::AppStyle::kLabelColumnWidth, -1));
  name->SetBackgroundColour(panel->GetBackgroundColour());
  name->SetForegroundColour(panel->GetForegroundColour());
  grid->Add(name, 0, wxALIGN_TOP | wxTOP, 1);
]===])
  string(FIND "${C}" "${ROW_LABEL_OLD}" RLPOS)
  if(RLPOS EQUAL -1)
    message(FATAL_ERROR "Could not locate property-row label styling")
  endif()
  string(REPLACE "${ROW_LABEL_OLD}" "${ROW_LABEL_NEW}" C "${C}")
endif()

string(REPLACE "wxSize(16, 16), wxBORDER_SIMPLE"
               "wxSize(ci_ui::AppStyle::kColorChipSize, ci_ui::AppStyle::kColorChipSize), wxBORDER_SIMPLE"
               C "${C}")
string(REPLACE "chip->SetMinSize(wxSize(16, 16));"
               "chip->SetMinSize(wxSize(ci_ui::AppStyle::kColorChipSize, ci_ui::AppStyle::kColorChipSize));"
               C "${C}")

# Make row text inherit the card palette. Guard on valueText to avoid duplicate edits.
if(NOT C MATCHES "wxStaticText \*valueText = new wxStaticText\(panel")
  set(VALUE_OLD [===[
    valueRow->Add(new wxStaticText(panel, wxID_ANY, value), 0,
                  wxALIGN_CENTER_VERTICAL);
    grid->Add(valueRow, 1, wxEXPAND);
  } else {
    wxStaticText *text = new wxStaticText(panel, wxID_ANY, value);
    grid->Add(text, 1, wxEXPAND);
  }
]===])
  set(VALUE_NEW [===[
    wxStaticText *valueText = new wxStaticText(panel, wxID_ANY, value);
    valueText->SetBackgroundColour(panel->GetBackgroundColour());
    valueText->SetForegroundColour(panel->GetForegroundColour());
    valueRow->Add(valueText, 0, wxALIGN_CENTER_VERTICAL);
    grid->Add(valueRow, 1, wxEXPAND);
  } else {
    wxStaticText *text = new wxStaticText(panel, wxID_ANY, value);
    text->SetBackgroundColour(panel->GetBackgroundColour());
    text->SetForegroundColour(panel->GetForegroundColour());
    grid->Add(text, 1, wxEXPAND);
  }
]===])
  string(FIND "${C}" "${VALUE_OLD}" VPOS)
  if(VPOS EQUAL -1)
    message(FATAL_ERROR "Could not locate property-row value styling")
  endif()
  string(REPLACE "${VALUE_OLD}" "${VALUE_NEW}" C "${C}")
endif()

# Insert theme implementation immediately before HideHoverInfoPanel.
if(NOT C MATCHES "CHARTINSPECTOR_APPSTYLE_V2")
  set(HIDE_MARK "void ChartInspectorPi::HideHoverInfoPanel() {")
  string(FIND "${C}" "${HIDE_MARK}" HIDE_POS)
  if(HIDE_POS EQUAL -1)
    message(FATAL_ERROR "Could not locate HideHoverInfoPanel")
  endif()
  set(THEME_CODE [===[
// CHARTINSPECTOR_APPSTYLE_V2
void ChartInspectorPi::ApplyHoverWindowTheme() {
  if (!m_hoverInfoWindow) return;
  const ci_ui::AppPalette palette = ci_ui::AppStyle::PaletteFor(m_colorScheme);
  m_hoverInfoWindow->SetBackgroundColour(palette.windowBackground);
  m_hoverInfoWindow->SetForegroundColour(palette.textPrimary);

  if (m_hoverInfoTitle) {
    m_hoverInfoTitle->SetBackgroundColour(palette.windowBackground);
    m_hoverInfoTitle->SetForegroundColour(palette.textPrimary);
  }
  if (m_hoverInfoMeta) {
    m_hoverInfoMeta->SetBackgroundColour(palette.windowBackground);
    m_hoverInfoMeta->SetForegroundColour(palette.textPrimary);
  }
  if (m_hoverInfoBody) {
    m_hoverInfoBody->SetBackgroundColour(palette.windowBackground);
    m_hoverInfoBody->SetForegroundColour(palette.textSecondary);
  }
  if (m_hoverInfoDetails) {
    m_hoverInfoDetails->SetBackgroundColour(palette.cardBackground);
    m_hoverInfoDetails->SetForegroundColour(palette.textPrimary);
    if (auto *card = dynamic_cast<ci_ui::RoundedPanel *>(m_hoverInfoDetails))
      card->SetCardColours(palette.cardBackground, palette.cardBorder);
    const wxWindowList &children = m_hoverInfoDetails->GetChildren();
    for (wxWindowList::const_iterator it = children.begin(); it != children.end(); ++it) {
      if (auto *text = dynamic_cast<wxStaticText *>(*it)) {
        text->SetBackgroundColour(palette.cardBackground);
        text->SetForegroundColour(palette.textPrimary);
      }
    }
  }
  m_hoverInfoWindow->Refresh(false);
}

]===])
  string(SUBSTRING "${C}" 0 ${HIDE_POS} HPRE)
  string(SUBSTRING "${C}" ${HIDE_POS} -1 HPOST)
  set(C "${HPRE}${THEME_CODE}${HPOST}")
endif()

# Replace flat details panel with a padded rounded card. This block was not
# changed by the associated-light patches.
if(NOT C MATCHES "new ci_ui::RoundedPanel")
  set(CARD_OLD [===[
    m_hoverInfoTitle =
        new wxStaticText(m_hoverInfoWindow, wxID_ANY, wxEmptyString);
    wxFont titleFont = m_hoverInfoTitle->GetFont();
    titleFont.SetWeight(wxFONTWEIGHT_BOLD);
    titleFont.SetPointSize(titleFont.GetPointSize() + 2);
    m_hoverInfoTitle->SetFont(titleFont);
    root->Add(m_hoverInfoTitle, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP, 12);

    m_hoverInfoMeta =
        new wxStaticText(m_hoverInfoWindow, wxID_ANY, wxEmptyString);
    wxFont primaryFont = m_hoverInfoMeta->GetFont();
    primaryFont.SetWeight(wxFONTWEIGHT_BOLD);
    primaryFont.SetPointSize(primaryFont.GetPointSize() + 1);
    m_hoverInfoMeta->SetFont(primaryFont);
    root->Add(m_hoverInfoMeta, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP, 7);

    root->Add(new wxStaticLine(m_hoverInfoWindow), 0,
              wxEXPAND | wxLEFT | wxRIGHT | wxTOP | wxBOTTOM, 10);

    m_hoverInfoDetails = new wxPanel(m_hoverInfoWindow, wxID_ANY);
    wxFlexGridSizer *grid = new wxFlexGridSizer(0, 2, 6, 16);
    grid->AddGrowableCol(1, 1);
    m_hoverInfoDetails->SetSizer(grid);
    root->Add(m_hoverInfoDetails, 0, wxEXPAND | wxLEFT | wxRIGHT, 12);

    m_hoverInfoBody =
        new wxStaticText(m_hoverInfoWindow, wxID_ANY, wxEmptyString);
    wxFont technicalFont = m_hoverInfoBody->GetFont();
    technicalFont.SetPointSize(std::max(7, technicalFont.GetPointSize() - 1));
    m_hoverInfoBody->SetFont(technicalFont);
    root->Add(m_hoverInfoBody, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP | wxBOTTOM,
              12);
]===])
  set(CARD_NEW [===[
    m_hoverInfoTitle =
        new wxStaticText(m_hoverInfoWindow, wxID_ANY, wxEmptyString);
    m_hoverInfoTitle->SetFont(
        ci_ui::AppStyle::TitleFont(m_hoverInfoTitle->GetFont()));
    root->Add(m_hoverInfoTitle, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP,
              ci_ui::AppStyle::kSpaceMd);

    m_hoverInfoMeta =
        new wxStaticText(m_hoverInfoWindow, wxID_ANY, wxEmptyString);
    m_hoverInfoMeta->SetFont(
        ci_ui::AppStyle::PrimaryFont(m_hoverInfoMeta->GetFont()));
    root->Add(m_hoverInfoMeta, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP,
              ci_ui::AppStyle::kSpaceSm);

    m_hoverInfoDetails =
        new ci_ui::RoundedPanel(m_hoverInfoWindow, ci_ui::AppStyle::kCardRadius);
    m_hoverInfoGrid = new wxFlexGridSizer(0, 2, 7, 18);
    m_hoverInfoGrid->AddGrowableCol(1, 1);
    wxBoxSizer *cardSizer = new wxBoxSizer(wxVERTICAL);
    cardSizer->Add(m_hoverInfoGrid, 1, wxEXPAND | wxALL,
                   ci_ui::AppStyle::kCardPadding);
    m_hoverInfoDetails->SetSizer(cardSizer);
    root->Add(m_hoverInfoDetails, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP,
              ci_ui::AppStyle::kSpaceMd);

    m_hoverInfoBody =
        new wxStaticText(m_hoverInfoWindow, wxID_ANY, wxEmptyString);
    m_hoverInfoBody->SetFont(
        ci_ui::AppStyle::TechnicalFont(m_hoverInfoBody->GetFont()));
    root->Add(m_hoverInfoBody, 0,
              wxEXPAND | wxLEFT | wxRIGHT | wxTOP | wxBOTTOM,
              ci_ui::AppStyle::kSpaceMd);
]===])
  string(FIND "${C}" "${CARD_OLD}" CARD_POS)
  if(CARD_POS EQUAL -1)
    message(FATAL_ERROR "Could not locate current hover-window layout")
  endif()
  string(REPLACE "${CARD_OLD}" "${CARD_NEW}" C "${C}")
endif()

if(NOT C MATCHES "m_hoverInfoWindow->Move\(p\);[\r\n ]+ApplyHoverWindowTheme\(\);")
  set(MOVE_OLD "    m_hoverInfoWindow->Move(p);\n  }")
  set(MOVE_NEW "    m_hoverInfoWindow->Move(p);\n    ApplyHoverWindowTheme();\n  }")
  string(FIND "${C}" "${MOVE_OLD}" MOVEPOS)
  if(MOVEPOS EQUAL -1)
    message(FATAL_ERROR "Could not locate hover-window creation tail")
  endif()
  string(REPLACE "${MOVE_OLD}" "${MOVE_NEW}" C "${C}")
endif()

# Property-grid lookup must now use the grid inside the card's outer sizer.
set(GRID_OLD [===[
  wxFlexGridSizer *grid =
      dynamic_cast<wxFlexGridSizer *>(m_hoverInfoDetails->GetSizer());
]===])
if(C MATCHES "dynamic_cast<wxFlexGridSizer \*>\(m_hoverInfoDetails->GetSizer\(\)\)")
  string(REPLACE "${GRID_OLD}" "  wxFlexGridSizer *grid = m_hoverInfoGrid;\n" C "${C}")
endif()

# Re-theme freshly created rows so they get the card palette immediately.
set(LAYOUT_ANCHOR [===[
    m_hoverInfoDetails->Show(grid->GetItemCount() > 0);
    m_hoverInfoDetails->Layout();
]===])
if(NOT C MATCHES "m_hoverInfoDetails->Layout\(\);[\r\n ]+ApplyHoverWindowTheme\(\);")
  string(FIND "${C}" "${LAYOUT_ANCHOR}" LAYOUTPOS)
  if(LAYOUTPOS EQUAL -1)
    message(FATAL_ERROR "Could not locate property-grid layout tail")
  endif()
  string(REPLACE "${LAYOUT_ANCHOR}"
                 "${LAYOUT_ANCHOR}    ApplyHoverWindowTheme();\n"
                 C "${C}")
endif()

if(NOT C MATCHES "m_hoverInfoGrid = nullptr")
  set(CLEAN_ANCHOR "  m_hoverInfoDetails = nullptr;\n")
  string(FIND "${C}" "${CLEAN_ANCHOR}" CLEANPOS)
  if(CLEANPOS EQUAL -1)
    message(FATAL_ERROR "Could not locate hover-info cleanup")
  endif()
  string(REPLACE "${CLEAN_ANCHOR}"
                 "${CLEAN_ANCHOR}  m_hoverInfoGrid = nullptr;\n"
                 C "${C}")
endif()

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed Chart Inspector AppStyle v2")
message(STATUS "  recovered cleanly from partial AppStyle v1 run")
message(STATUS "  reusable AppStyle tokens live under src/ui")
message(STATUS "  reusable 8px RoundedPanel card installed")
message(STATUS "  4/8/12/16/24 spacing and shared typography applied")
message(STATUS "  Day/Dusk/Night palette follows OpenCPN colour scheme")
message(STATUS "  Chart Inspector is the reference UI for future plugins")
