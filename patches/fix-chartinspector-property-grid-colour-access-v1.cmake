set(CPP "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()

file(READ "${CPP}" C)

if(C MATCHES "CHARTINSPECTOR_PROPERTY_GRID_COLOUR_ACCESS_FIX_V1")
  message(STATUS "Chart Inspector property-grid colour access fix v1 already installed")
  return()
endif()
if(NOT C MATCHES "CHARTINSPECTOR_PROPERTY_GRID_V1")
  message(FATAL_ERROR "Property grid v1 must be installed first")
endif()

set(OLD_HELPER [===[
static void CI_AddPropertyRow(ChartInspectorPi *plugin, wxPanel *panel,
                              wxFlexGridSizer *grid, const wxString &label,
                              const wxString &value,
                              const wxString &colourRaw = wxEmptyString) {
  if (!plugin || !panel || !grid || value.IsEmpty()) return;

  wxStaticText *name = new wxStaticText(panel, wxID_ANY, label);
  wxFont labelFont = name->GetFont();
  labelFont.SetWeight(wxFONTWEIGHT_BOLD);
  name->SetFont(labelFont);
  grid->Add(name, 0, wxALIGN_TOP | wxTOP, 1);

  if (!colourRaw.IsEmpty()) {
    wxBoxSizer *valueRow = new wxBoxSizer(wxHORIZONTAL);
    wxStringTokenizer colours(colourRaw, ",", wxTOKEN_STRTOK);
    while (colours.HasMoreTokens()) {
      wxString token = colours.GetNextToken();
      token.Trim(true);
      token.Trim(false);
      wxPanel *chip = new wxPanel(panel, wxID_ANY, wxDefaultPosition,
                                  wxSize(16, 16), wxBORDER_SIMPLE);
      chip->SetMinSize(wxSize(16, 16));
      chip->SetBackgroundColour(plugin->SignalColour(token));
      valueRow->Add(chip, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 5);
    }
    valueRow->Add(new wxStaticText(panel, wxID_ANY, value), 0,
                  wxALIGN_CENTER_VERTICAL);
    grid->Add(valueRow, 1, wxEXPAND);
  } else {
    wxStaticText *text = new wxStaticText(panel, wxID_ANY, value);
    grid->Add(text, 1, wxEXPAND);
  }
}
]===])

set(NEW_HELPER [===[
// CHARTINSPECTOR_PROPERTY_GRID_COLOUR_ACCESS_FIX_V1
static void CI_AddPropertyRow(wxPanel *panel, wxFlexGridSizer *grid,
                              const wxString &label, const wxString &value,
                              const std::vector<wxColour> &colourChips = {}) {
  if (!panel || !grid || value.IsEmpty()) return;

  wxStaticText *name = new wxStaticText(panel, wxID_ANY, label);
  wxFont labelFont = name->GetFont();
  labelFont.SetWeight(wxFONTWEIGHT_BOLD);
  name->SetFont(labelFont);
  grid->Add(name, 0, wxALIGN_TOP | wxTOP, 1);

  if (!colourChips.empty()) {
    wxBoxSizer *valueRow = new wxBoxSizer(wxHORIZONTAL);
    for (const wxColour &colour : colourChips) {
      wxPanel *chip = new wxPanel(panel, wxID_ANY, wxDefaultPosition,
                                  wxSize(16, 16), wxBORDER_SIMPLE);
      chip->SetMinSize(wxSize(16, 16));
      chip->SetBackgroundColour(colour);
      valueRow->Add(chip, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 5);
    }
    valueRow->Add(new wxStaticText(panel, wxID_ANY, value), 0,
                  wxALIGN_CENTER_VERTICAL);
    grid->Add(valueRow, 1, wxEXPAND);
  } else {
    wxStaticText *text = new wxStaticText(panel, wxID_ANY, value);
    grid->Add(text, 1, wxEXPAND);
  }
}
]===])

string(FIND "${C}" "${OLD_HELPER}" HPOS)
if(HPOS EQUAL -1)
  message(FATAL_ERROR "Could not locate property row helper")
endif()
string(REPLACE "${OLD_HELPER}" "${NEW_HELPER}" C "${C}")

set(OLD_CALL [===[
      CI_AddPropertyRow(this, m_hoverInfoDetails, grid, label, value,
                        label == "Color" ? colourRaw : wxEmptyString);
]===])

set(NEW_CALL [===[
      std::vector<wxColour> colourChips;
      if (label == "Color" && !colourRaw.IsEmpty()) {
        wxStringTokenizer colours(colourRaw, ",", wxTOKEN_STRTOK);
        while (colours.HasMoreTokens()) {
          wxString token = colours.GetNextToken();
          token.Trim(true);
          token.Trim(false);
          colourChips.push_back(SignalColour(token));
        }
      }
      CI_AddPropertyRow(m_hoverInfoDetails, grid, label, value, colourChips);
]===])

string(FIND "${C}" "${OLD_CALL}" CPOS)
if(CPOS EQUAL -1)
  message(FATAL_ERROR "Could not locate property row call")
endif()
string(REPLACE "${OLD_CALL}" "${NEW_CALL}" C "${C}")

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed Chart Inspector property-grid colour access fix v1")
message(STATUS "  private SignalColour remains encapsulated")
message(STATUS "  colour chips are calculated inside ChartInspectorPi")
message(STATUS "  property-row helper now receives ready-to-use colours")
