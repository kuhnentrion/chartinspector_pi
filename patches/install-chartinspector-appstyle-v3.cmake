set(ROOT "${CMAKE_CURRENT_LIST_DIR}/..")
set(HDR "${ROOT}/src/chartinspector_pi.h")
set(CPP "${ROOT}/src/chartinspector_pi.cpp")
set(CMAKE_FILE "${ROOT}/CMakeLists.txt")
set(APP_STYLE_H "${ROOT}/src/ui/app_style.h")
set(APP_STYLE_CPP "${ROOT}/src/ui/app_style.cpp")
set(ROUNDED_H "${ROOT}/src/ui/rounded_panel.h")
set(ROUNDED_CPP "${ROOT}/src/ui/rounded_panel.cpp")

foreach(P "${HDR}" "${CPP}" "${CMAKE_FILE}" "${APP_STYLE_H}" "${APP_STYLE_CPP}" "${ROUNDED_H}" "${ROUNDED_CPP}")
  if(NOT EXISTS "${P}")
    message(FATAL_ERROR "Missing ${P}; run AppStyle v2 once before this recovery patch")
  endif()
endforeach()

file(READ "${HDR}" H)
file(READ "${CPP}" C)
file(READ "${CMAKE_FILE}" M)

string(FIND "${C}" "CHARTINSPECTOR_APPSTYLE_V3" ALREADY)
if(NOT ALREADY EQUAL -1)
  message(STATUS "Chart Inspector AppStyle v3 already installed")
  return()
endif()

string(FIND "${C}" "CHARTINSPECTOR_PROPERTY_GRID_V1" HAS_GRID)
if(HAS_GRID EQUAL -1)
  message(FATAL_ERROR "Property grid v1 must be installed first")
endif()

# Ensure CMake includes the reusable UI sources. v2 normally already did this.
string(FIND "${M}" "src/ui/app_style.cpp" HAS_UI_CMAKE)
if(HAS_UI_CMAKE EQUAL -1)
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

# Recover/complete header changes from the partial v2 run.
string(FIND "${H}" "#include <wx/sizer.h>" HAS_SIZER_INCLUDE)
if(HAS_SIZER_INCLUDE EQUAL -1)
  string(REPLACE "#include <wx/string.h>" "#include <wx/string.h>\n#include <wx/sizer.h>" H "${H}")
endif()

string(FIND "${H}" "void ApplyHoverWindowTheme();" HAS_THEME_DECL)
if(HAS_THEME_DECL EQUAL -1)
  set(UPDATE_DECL "  void UpdateHoverInfoPanel(")
  string(FIND "${H}" "${UPDATE_DECL}" DPOS)
  if(DPOS EQUAL -1)
    message(FATAL_ERROR "Could not locate UpdateHoverInfoPanel declaration")
  endif()
  string(SUBSTRING "${H}" 0 ${DPOS} HPRE)
  string(SUBSTRING "${H}" ${DPOS} -1 HPOST)
  set(H "${HPRE}  void ApplyHoverWindowTheme();\n${HPOST}")
endif()

string(FIND "${H}" "m_hoverInfoGrid" HAS_GRID_MEMBER)
if(HAS_GRID_MEMBER EQUAL -1)
  set(MEMBER_ANCHOR "  wxPanel *m_hoverInfoDetails = nullptr;\n")
  string(FIND "${H}" "${MEMBER_ANCHOR}" MEMPOS)
  if(MEMPOS EQUAL -1)
    message(FATAL_ERROR "Could not locate m_hoverInfoDetails member")
  endif()
  string(REPLACE "${MEMBER_ANCHOR}" "${MEMBER_ANCHOR}  wxFlexGridSizer *m_hoverInfoGrid = nullptr;\n" H "${H}")
endif()
file(WRITE "${HDR}" "${H}")

# Includes.
string(FIND "${C}" "ui/app_style.h" HAS_STYLE_INCLUDE)
if(HAS_STYLE_INCLUDE EQUAL -1)
  string(REPLACE "#include \"chartinspector_pi.h\"" "#include \"chartinspector_pi.h\"\n#include \"ui/app_style.h\"\n#include \"ui/rounded_panel.h\"" C "${C}")
endif()

# Day/Dusk/Night changes update the hover window too.
string(FIND "${C}" "  ApplyInfoTheme();\n  ApplyHoverWindowTheme();" HAS_SCHEME_CALL)
if(HAS_SCHEME_CALL EQUAL -1)
  set(SCHEME_OLD "  ApplyInfoTheme();\n  if (m_infoPanel && m_infoPanel->IsShown()) {")
  set(SCHEME_NEW "  ApplyInfoTheme();\n  ApplyHoverWindowTheme();\n  if (m_infoPanel && m_infoPanel->IsShown()) {")
  string(FIND "${C}" "${SCHEME_OLD}" CSPOS)
  if(CSPOS EQUAL -1)
    message(FATAL_ERROR "Could not locate SetColorScheme theme call")
  endif()
  string(REPLACE "${SCHEME_OLD}" "${SCHEME_NEW}" C "${C}")
endif()

# Shared property-row typography and label column.
string(FIND "${C}" "kLabelColumnWidth" HAS_LABEL_STYLE)
if(HAS_LABEL_STYLE EQUAL -1)
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

string(REPLACE "wxSize(16, 16), wxBORDER_SIMPLE" "wxSize(ci_ui::AppStyle::kColorChipSize, ci_ui::AppStyle::kColorChipSize), wxBORDER_SIMPLE" C "${C}")
string(REPLACE "chip->SetMinSize(wxSize(16, 16));" "chip->SetMinSize(wxSize(ci_ui::AppStyle::kColorChipSize, ci_ui::AppStyle::kColorChipSize));" C "${C}")

# No regex here: literal presence check avoids CMake regex escaping problems.
string(FIND "${C}" "wxStaticText *valueText = new wxStaticText(panel" HAS_VALUE_STYLE)
if(HAS_VALUE_STYLE EQUAL -1)
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

# Shared theme implementation.
set(HIDE_MARK "void ChartInspectorPi::HideHoverInfoPanel() {")
string(FIND "${C}" "void ChartInspectorPi::ApplyHoverWindowTheme()" HAS_THEME_IMPL)
if(HAS_THEME_IMPL EQUAL -1)
  string(FIND "${C}" "${HIDE_MARK}" HIDE_POS)
  if(HIDE_POS EQUAL -1)
    message(FATAL_ERROR "Could not locate HideHoverInfoPanel")
  endif()
  set(THEME_CODE [===[
// CHARTINSPECTOR_APPSTYLE_V3
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

# Replace the flat white property panel with a padded rounded card.
string(FIND "${C}" "new ci_ui::RoundedPanel" HAS_ROUNDED_CARD)
if(HAS_ROUNDED_CARD EQUAL -1)
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

# Theme immediately after first window creation.
string(FIND "${C}" "    m_hoverInfoWindow->Move(p);\n    ApplyHoverWindowTheme();" HAS_INITIAL_THEME)
if(HAS_INITIAL_THEME EQUAL -1)
  set(MOVE_OLD "    m_hoverInfoWindow->Move(p);\n  }")
  set(MOVE_NEW "    m_hoverInfoWindow->Move(p);\n    ApplyHoverWindowTheme();\n  }")
  string(FIND "${C}" "${MOVE_OLD}" MOVEPOS)
  if(MOVEPOS EQUAL -1)
    message(FATAL_ERROR "Could not locate hover-window creation tail")
  endif()
  string(REPLACE "${MOVE_OLD}" "${MOVE_NEW}" C "${C}")
endif()

# The rounded card owns an outer padding sizer, so keep a direct pointer to the grid.
set(GRID_OLD [===[
  wxFlexGridSizer *grid =
      dynamic_cast<wxFlexGridSizer *>(m_hoverInfoDetails->GetSizer());
]===])
string(FIND "${C}" "${GRID_OLD}" GRIDPOS)
if(NOT GRIDPOS EQUAL -1)
  string(REPLACE "${GRID_OLD}" "  wxFlexGridSizer *grid = m_hoverInfoGrid;\n" C "${C}")
endif()

# Newly generated row controls inherit the current card palette.
string(FIND "${C}" "    m_hoverInfoDetails->Layout();\n    ApplyHoverWindowTheme();" HAS_ROW_THEME)
if(HAS_ROW_THEME EQUAL -1)
  set(LAYOUT_ANCHOR [===[
    m_hoverInfoDetails->Show(grid->GetItemCount() > 0);
    m_hoverInfoDetails->Layout();
]===])
  string(FIND "${C}" "${LAYOUT_ANCHOR}" LAYOUTPOS)
  if(LAYOUTPOS EQUAL -1)
    message(FATAL_ERROR "Could not locate property-grid layout tail")
  endif()
  string(REPLACE "${LAYOUT_ANCHOR}" "${LAYOUT_ANCHOR}    ApplyHoverWindowTheme();\n" C "${C}")
endif()

string(FIND "${C}" "m_hoverInfoGrid = nullptr" HAS_GRID_CLEANUP)
if(HAS_GRID_CLEANUP EQUAL -1)
  set(CLEAN_ANCHOR "  m_hoverInfoDetails = nullptr;\n")
  string(FIND "${C}" "${CLEAN_ANCHOR}" CLEANPOS)
  if(CLEANPOS EQUAL -1)
    message(FATAL_ERROR "Could not locate hover-info cleanup")
  endif()
  string(REPLACE "${CLEAN_ANCHOR}" "${CLEAN_ANCHOR}  m_hoverInfoGrid = nullptr;\n" C "${C}")
endif()

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed Chart Inspector AppStyle v3")
message(STATUS "  recovered partial v2 install without regex matching")
message(STATUS "  reusable AppStyle and RoundedPanel components are active")
message(STATUS "  property card uses 8px radius and 12px internal padding")
message(STATUS "  shared 4/8/12/16/24 spacing and typography are active")
message(STATUS "  Day/Dusk/Night palette follows OpenCPN")
message(STATUS "  Chart Inspector remains the reference UI for future plugins")
