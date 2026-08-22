set(HDR "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.h")
set(CPP "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.cpp")
foreach(P "${HDR}" "${CPP}")
  if(NOT EXISTS "${P}")
    message(FATAL_ERROR "Missing ${P}")
  endif()
endforeach()

file(READ "${HDR}" H)
file(READ "${CPP}" C)

if(C MATCHES "CHARTINSPECTOR_PROPERTY_GRID_V1")
  message(STATUS "Chart Inspector property grid v1 already installed")
  return()
endif()
if(NOT C MATCHES "CHARTINSPECTOR_NAVIGATION_INFO_V1")
  message(FATAL_ERROR "Navigation info v1 must be installed first")
endif()
if(NOT C MATCHES "CHARTINSPECTOR_NAV_DEPTH_BUILD_FIX_V1")
  message(FATAL_ERROR "Navigation depth build fix v1 must be installed first")
endif()

set(H_OLD [===[
  wxFrame *m_hoverInfoWindow = nullptr;
  wxStaticText *m_hoverInfoTitle = nullptr;
  wxStaticText *m_hoverInfoMeta = nullptr;
  wxStaticText *m_hoverInfoBody = nullptr;
]===])
set(H_NEW [===[
  wxFrame *m_hoverInfoWindow = nullptr;
  wxStaticText *m_hoverInfoTitle = nullptr;
  wxStaticText *m_hoverInfoMeta = nullptr;
  wxPanel *m_hoverInfoDetails = nullptr;
  wxStaticText *m_hoverInfoBody = nullptr;
]===])
string(FIND "${H}" "${H_OLD}" HPOS)
if(HPOS EQUAL -1)
  message(FATAL_ERROR "Could not locate hover window member fields")
endif()
string(REPLACE "${H_OLD}" "${H_NEW}" H "${H}")
file(WRITE "${HDR}" "${H}")

set(START_MARK "// CHARTINSPECTOR_SIMPLE_HOVER_WINDOW_V1")
set(END_MARK "void ChartInspectorPi::ClearHoverGeometry() {")
string(FIND "${C}" "${START_MARK}" START)
string(FIND "${C}" "${END_MARK}" END)
if(START EQUAL -1 OR END EQUAL -1 OR END LESS START)
  message(FATAL_ERROR "Could not locate current navigation hover window block")
endif()

set(NEW_BLOCK [===[
// CHARTINSPECTOR_SIMPLE_HOVER_WINDOW_V1
// CHARTINSPECTOR_NAVIGATION_INFO_V1
// CHARTINSPECTOR_NAV_DEPTH_BUILD_FIX_V1
// CHARTINSPECTOR_PROPERTY_GRID_V1
namespace {

struct CI_RawAttribute {
  wxString acronym;
  wxString value;
};

static std::vector<CI_RawAttribute> CI_ParseRawAttributes(
    const wxString &attributes) {
  std::vector<CI_RawAttribute> result;
  wxStringTokenizer lines(attributes, "\n", wxTOKEN_STRTOK);
  while (lines.HasMoreTokens()) {
    wxString line = lines.GetNextToken();
    line.Trim(true);
    line.Trim(false);
    if (line.IsEmpty()) continue;
    const int equals = line.Find('=');
    if (equals == wxNOT_FOUND) continue;
    wxString acronym = line.Left(equals).Upper();
    wxString value = line.Mid(equals + 1);
    acronym.Trim(true);
    acronym.Trim(false);
    value.Trim(true);
    value.Trim(false);
    if (!acronym.IsEmpty()) result.push_back({acronym, value});
  }
  return result;
}

static bool CI_ParseNumber(wxString raw, double *value) {
  if (!value) return false;
  raw.Trim(true);
  raw.Trim(false);
  raw.Replace(",", ".");
  return raw.ToDouble(value);
}

static wxString CI_UserDepth(double metres) {
  return wxString::Format("%g m", metres);
}

static wxString CI_MetricLength(const wxString &label,
                                const wxString &rawValue) {
  double metres = 0.0;
  if (!CI_ParseNumber(rawValue, &metres)) return wxEmptyString;
  return label + ": " + wxString::Format("%g m", metres);
}

static wxString CI_DepthLike(const wxString &label,
                             const wxString &rawValue) {
  double metres = 0.0;
  if (!CI_ParseNumber(rawValue, &metres))
    return label + ": " + rawValue;
  return label + ": " + CI_UserDepth(metres);
}

static wxString CI_CleanDecodedCodes(const wxString &input) {
  wxString out;
  for (size_t i = 0; i < input.length();) {
    if (input[i] == '(') {
      size_t j = i + 1;
      bool hasDigit = false;
      while (j < input.length() && input[j] >= '0' && input[j] <= '9') {
        hasDigit = true;
        ++j;
      }
      if (hasDigit && j < input.length() && input[j] == ')') {
        i = j + 1;
        continue;
      }
    }
    out += input[i++];
  }
  while (out.Replace("  ", " ")) {}
  out.Replace(" ,", ",");
  out.Trim(true);
  out.Trim(false);
  return out;
}

static wxString CI_ColourName(long code) {
  switch (code) {
    case 1: return "White";
    case 2: return "Black";
    case 3: return "Red";
    case 4: return "Green";
    case 5: return "Blue";
    case 6: return "Yellow";
    case 7: return "Grey";
    case 8: return "Brown";
    case 9: return "Amber";
    case 10: return "Violet";
    case 11: return "Orange";
    case 12: return "Magenta";
    case 13: return "Pink";
    default: return wxEmptyString;
  }
}

static wxString CI_DecodeColours(const wxString &rawValue) {
  wxString result;
  wxStringTokenizer values(rawValue, ",", wxTOKEN_STRTOK);
  while (values.HasMoreTokens()) {
    wxString token = values.GetNextToken();
    token.Trim(true);
    token.Trim(false);
    long code = 0;
    wxString name;
    if (token.ToLong(&code)) name = CI_ColourName(code);
    if (name.IsEmpty()) name = CI_CleanDecodedCodes(token);
    if (name.IsEmpty()) continue;
    if (!result.IsEmpty()) result += ", ";
    result += name;
  }
  return result;
}

static wxString CI_LightCharacteristic(const wxString &rawValue) {
  long code = 0;
  if (!rawValue.ToLong(&code)) return CI_CleanDecodedCodes(rawValue);
  switch (code) {
    case 1: return "Fixed";
    case 2: return "Flashing";
    case 3: return "Long-flashing";
    case 4: return "Quick-flashing";
    case 5: return "Very quick-flashing";
    case 6: return "Ultra quick-flashing";
    case 7: return "Isophase";
    case 8: return "Occulting";
    case 9: return "Interrupted quick-flashing";
    case 10: return "Interrupted very quick-flashing";
    case 11: return "Interrupted ultra quick-flashing";
    case 12: return "Morse";
    case 13: return "Fixed and flashing";
    case 14: return "Flashing and long-flashing";
    case 28: return "Alternating";
    case 29: return "Fixed and alternating flashing";
    default: return CI_CleanDecodedCodes(rawValue);
  }
}

static wxString CI_FriendlyAttribute(const S57Catalog &catalog,
                                     const wxString &acronym,
                                     const wxString &rawValue) {
  if (acronym == "VALSOU") return CI_DepthLike("Depth", rawValue);
  if (acronym == "DRVAL1") return CI_DepthLike("Minimum depth", rawValue);
  if (acronym == "DRVAL2") return CI_DepthLike("Maximum depth", rawValue);
  if (acronym == "VERCLR") return CI_DepthLike("Vertical clearance", rawValue);
  if (acronym == "VERCSA")
    return CI_DepthLike("Safe vertical clearance", rawValue);
  if (acronym == "VERCCL")
    return CI_DepthLike("Closed vertical clearance", rawValue);
  if (acronym == "VERCOP")
    return CI_DepthLike("Open vertical clearance", rawValue);
  if (acronym == "HORCLR") return CI_MetricLength("Horizontal clearance", rawValue);
  if (acronym == "HEIGHT") return CI_MetricLength("Height", rawValue);
  if (acronym == "ELEVAT") return CI_MetricLength("Elevation", rawValue);
  if (acronym == "HORLEN") return CI_MetricLength("Length", rawValue);
  if (acronym == "HORWID") return CI_MetricLength("Width", rawValue);
  if (acronym == "VERLEN") return CI_MetricLength("Vertical length", rawValue);
  if (acronym == "COLOUR") return "Color: " + CI_DecodeColours(rawValue);
  if (acronym == "LITCHR")
    return "Light characteristic: " + CI_LightCharacteristic(rawValue);
  if (acronym == "SIGPER") {
    double seconds = 0.0;
    if (CI_ParseNumber(rawValue, &seconds))
      return "Period: " + wxString::Format("%g s", seconds);
  }
  if (acronym == "VALNMR") {
    double nm = 0.0;
    if (CI_ParseNumber(rawValue, &nm))
      return "Nominal range: " + wxString::Format("%g NM", nm);
  }
  if (acronym == "ORIENT" || acronym == "SECTR1" || acronym == "SECTR2") {
    double degrees = 0.0;
    if (CI_ParseNumber(rawValue, &degrees)) {
      wxString label = acronym == "ORIENT" ? "Orientation" :
                       acronym == "SECTR1" ? "Sector start" : "Sector end";
      return label + ": " + wxString::Format("%g deg", degrees);
    }
  }

  return CI_CleanDecodedCodes(
      catalog.FormatAttributes(acronym + "=" + rawValue, nullptr));
}

static int CI_NavigationPriority(const wxString &acronym) {
  if (acronym == "WATLEV" || acronym == "EXPSOU" ||
      acronym == "QUASOU" || acronym == "RESTRN" ||
      acronym == "STATUS")
    return 0;
  if (acronym.StartsWith("CAT") && acronym != "CATGEO") return 1;
  if (acronym == "FUNCTN" || acronym == "CONVIS" || acronym == "NATCON")
    return 1;
  if (acronym == "LITCHR" || acronym == "COLOUR" || acronym == "COLPAT" ||
      acronym == "SIGGRP" || acronym == "SIGPER" || acronym == "VALNMR" ||
      acronym == "ORIENT" || acronym == "SECTR1" || acronym == "SECTR2")
    return 2;
  if (acronym == "HORCLR" || acronym == "HEIGHT" || acronym == "ELEVAT" ||
      acronym == "HORLEN" || acronym == "HORWID" || acronym == "VERLEN")
    return 3;
  if (acronym == "INFORM" || acronym == "NINFOM" ||
      acronym == "DATSTA" || acronym == "DATEND" ||
      acronym == "PERSTA" || acronym == "PEREND")
    return 4;
  return 99;
}

static bool CI_IsPrimaryNavigationAttribute(const wxString &acronym) {
  return acronym == "VALSOU" || acronym == "VERCSA" ||
         acronym == "VERCLR" || acronym == "VERCCL" ||
         acronym == "VERCOP" || acronym == "DRVAL1" ||
         acronym == "DRVAL2";
}

static bool CI_IsTechnicalAttribute(const wxString &acronym) {
  return acronym == "CATGEO" || acronym == "SCAMIN" ||
         acronym == "SCAMAX" || acronym == "SORDAT" ||
         acronym == "SORIND" || acronym == "RECDAT" ||
         acronym == "RECIND" || acronym == "GRUP" ||
         acronym.StartsWith("$");
}

struct CI_NavigationInfo {
  wxString primary;
  wxString details;
  wxString technical;
};

static CI_NavigationInfo CI_BuildNavigationInfo(
    const S57Catalog &catalog, const wxString &feature,
    const wxString &objectName, const wxString &attributes,
    int geometryType, bool showTechnical) {
  CI_NavigationInfo info;
  const auto raw = CI_ParseRawAttributes(attributes);

  static const char *primaryOrder[] = {
      "VALSOU", "VERCSA", "VERCLR", "VERCCL", "VERCOP", "DRVAL1", "DRVAL2"};
  wxString primaryAcronym;
  for (const char *wanted : primaryOrder) {
    for (const auto &attribute : raw) {
      if (attribute.acronym == wanted) {
        info.primary = CI_FriendlyAttribute(catalog, attribute.acronym,
                                            attribute.value);
        primaryAcronym = attribute.acronym;
        break;
      }
    }
    if (!info.primary.IsEmpty()) break;
  }

  for (int priority = 0; priority <= 4; ++priority) {
    for (const auto &attribute : raw) {
      if (attribute.acronym == primaryAcronym ||
          CI_IsPrimaryNavigationAttribute(attribute.acronym) ||
          attribute.acronym == "OBJNAM" || attribute.acronym == "NOBJNM" ||
          CI_IsTechnicalAttribute(attribute.acronym) ||
          CI_NavigationPriority(attribute.acronym) != priority)
        continue;
      const wxString line = CI_FriendlyAttribute(
          catalog, attribute.acronym, attribute.value);
      if (line.IsEmpty()) continue;
      if (!info.details.IsEmpty()) info.details += "\n";
      info.details += line;
    }
  }

  if (!objectName.IsEmpty()) {
    if (!info.details.IsEmpty()) info.details = "Name: " + objectName + "\n" + info.details;
    else info.details = "Name: " + objectName;
  }

  if (showTechnical) {
    const wxString geometry = geometryType == 3 ? "Area" :
                              geometryType == 2 ? "Line" : "Point";
    info.technical = "S-57 class: " + feature + "\nGeometry: " + geometry;
    for (const auto &attribute : raw) {
      if (!CI_IsTechnicalAttribute(attribute.acronym)) continue;
      info.technical += "\n" + attribute.acronym + ": " + attribute.value;
    }
  }

  return info;
}

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

}  // namespace

void ChartInspectorPi::HideHoverInfoPanel() {
  m_hoverInfoKey.clear();
  if (m_hoverInfoWindow) m_hoverInfoWindow->Hide();
}

void ChartInspectorPi::UpdateHoverInfoPanel(const wxString &feature,
                                            const wxString &objectName,
                                            const wxString &attributes,
                                            int geometryType) {
  if (!m_enabled || feature.IsEmpty()) {
    HideHoverInfoPanel();
    return;
  }

  wxWindow *canvas = GetOCPNCanvasWindow();
  if (!canvas) return;

  if (!m_hoverInfoWindow) {
    m_hoverInfoWindow = new wxFrame(
        canvas, wxID_ANY, "Chart Inspector", wxDefaultPosition,
        wxSize(390, 230),
        wxCAPTION | wxCLOSE_BOX | wxRESIZE_BORDER | wxFRAME_TOOL_WINDOW |
            wxSTAY_ON_TOP);

    wxBoxSizer *root = new wxBoxSizer(wxVERTICAL);

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

    m_hoverInfoWindow->SetSizer(root);
    m_hoverInfoWindow->SetMinSize(wxSize(330, 160));

    m_hoverInfoWindow->Bind(wxEVT_CLOSE_WINDOW, [this](wxCloseEvent &event) {
      if (m_hoverInfoWindow) m_hoverInfoWindow->Hide();
      m_hoverInfoKey.clear();
      event.Veto();
    });

    const wxPoint p = canvas->ClientToScreen(wxPoint(24, 80));
    m_hoverInfoWindow->Move(p);
  }

  wxString title = m_s57Catalog.ObjectName(feature);
  if (title.IsEmpty()) title = feature;
  m_hoverInfoTitle->SetLabel(CI_CleanDecodedCodes(title));

  const CI_NavigationInfo info = CI_BuildNavigationInfo(
      m_s57Catalog, feature, objectName, attributes, geometryType,
      m_showTechnicalData);

  m_hoverInfoMeta->SetLabel(info.primary);
  m_hoverInfoMeta->Show(!info.primary.IsEmpty());

  wxFlexGridSizer *grid =
      dynamic_cast<wxFlexGridSizer *>(m_hoverInfoDetails->GetSizer());
  if (grid) {
    grid->Clear(true);
    const wxString colourRaw =
        m_s57Catalog.RawAttributeValue(attributes, "COLOUR");
    wxStringTokenizer lines(info.details, "\n", wxTOKEN_STRTOK);
    while (lines.HasMoreTokens()) {
      wxString line = lines.GetNextToken();
      line.Trim(true);
      line.Trim(false);
      if (line.IsEmpty()) continue;
      const int colon = line.Find(':');
      wxString label;
      wxString value;
      if (colon == wxNOT_FOUND) {
        label = "Info";
        value = line;
      } else {
        label = line.Left(colon);
        value = line.Mid(colon + 1);
        label.Trim(true);
        label.Trim(false);
        value.Trim(true);
        value.Trim(false);
      }
      CI_AddPropertyRow(this, m_hoverInfoDetails, grid, label, value,
                        label == "Color" ? colourRaw : wxEmptyString);
    }
    m_hoverInfoDetails->Show(grid->GetItemCount() > 0);
    m_hoverInfoDetails->Layout();
  }

  if (m_showTechnicalData && !info.technical.IsEmpty()) {
    m_hoverInfoBody->SetLabel("Technical\n" + info.technical);
    m_hoverInfoBody->Show();
  } else {
    m_hoverInfoBody->SetLabel(wxEmptyString);
    m_hoverInfoBody->Hide();
  }

  m_hoverInfoWindow->Layout();
  m_hoverInfoWindow->Fit();
  wxSize size = m_hoverInfoWindow->GetSize();
  size.SetWidth(std::max(350, std::min(500, size.GetWidth())));
  size.SetHeight(std::max(155, std::min(560, size.GetHeight())));
  m_hoverInfoWindow->SetSize(size);
  m_hoverInfoWindow->Layout();

  if (!m_hoverInfoWindow->IsShown()) m_hoverInfoWindow->Show();
}

]===])

string(SUBSTRING "${C}" 0 ${START} PRE)
string(SUBSTRING "${C}" ${END} -1 POST)
set(C "${PRE}${NEW_BLOCK}${POST}")

set(CLEAN_OLD [===[
  m_hoverInfoWindow = nullptr;
  m_hoverInfoTitle = nullptr;
  m_hoverInfoMeta = nullptr;
  m_hoverInfoBody = nullptr;
]===])
set(CLEAN_NEW [===[
  m_hoverInfoWindow = nullptr;
  m_hoverInfoTitle = nullptr;
  m_hoverInfoMeta = nullptr;
  m_hoverInfoDetails = nullptr;
  m_hoverInfoBody = nullptr;
]===])
string(FIND "${C}" "${CLEAN_OLD}" CPOS)
if(CPOS EQUAL -1)
  message(FATAL_ERROR "Could not locate hover window cleanup")
endif()
string(REPLACE "${CLEAN_OLD}" "${CLEAN_NEW}" C "${C}")

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed Chart Inspector property grid v1")
message(STATUS "  labels and values are aligned in separate columns")
message(STATUS "  S-57 numeric decode suffixes are hidden in normal view")
message(STATUS "  color values use clean names plus visual color chips")
message(STATUS "  depth parsing accepts decimal point or comma")
message(STATUS "  technical metadata remains optional below the navigation data")
