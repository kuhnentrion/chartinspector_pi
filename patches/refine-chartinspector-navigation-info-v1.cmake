set(HDR "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.h")
set(CPP "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.cpp")
foreach(P "${HDR}" "${CPP}")
  if(NOT EXISTS "${P}")
    message(FATAL_ERROR "Missing ${P}")
  endif()
endforeach()

file(READ "${HDR}" H)
file(READ "${CPP}" C)

if(C MATCHES "CHARTINSPECTOR_NAVIGATION_INFO_V1")
  message(STATUS "Chart Inspector navigation info v1 already installed")
  return()
endif()

if(NOT C MATCHES "CHARTINSPECTOR_SIMPLE_HOVER_WINDOW_V1")
  message(FATAL_ERROR "Simple floating hover window v1 must be installed first")
endif()

set(START_MARK "// CHARTINSPECTOR_SIMPLE_HOVER_WINDOW_V1")
set(END_MARK "void ChartInspectorPi::ClearHoverGeometry() {")
string(FIND "${C}" "${START_MARK}" START)
string(FIND "${C}" "${END_MARK}" END)
if(START EQUAL -1 OR END EQUAL -1 OR END LESS START)
  message(FATAL_ERROR "Could not locate current hover window implementation")
endif()

set(WINDOW_CODE [===[
// CHARTINSPECTOR_SIMPLE_HOVER_WINDOW_V1
// CHARTINSPECTOR_NAVIGATION_INFO_V1
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

static wxString CI_UserDepth(double metres) {
  const double value = toUsrDepth_Plugin(metres);
  return wxString::Format("%g ", value) + getUsrDepthUnit_Plugin();
}

static wxString CI_MetricLength(const wxString &label,
                                const wxString &rawValue) {
  double metres = 0.0;
  if (!rawValue.ToDouble(&metres)) return wxEmptyString;
  return label + ": " + wxString::Format("%g m", metres);
}

static wxString CI_DepthLike(const wxString &label,
                             const wxString &rawValue) {
  double metres = 0.0;
  if (!rawValue.ToDouble(&metres)) return wxEmptyString;
  return label + ": " + CI_UserDepth(metres);
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
  if (acronym == "SIGPER") {
    double seconds = 0.0;
    if (rawValue.ToDouble(&seconds))
      return "Period: " + wxString::Format("%g s", seconds);
  }
  if (acronym == "VALNMR") {
    double nm = 0.0;
    if (rawValue.ToDouble(&nm))
      return "Nominal range: " + wxString::Format("%g NM", nm);
  }
  if (acronym == "ORIENT" || acronym == "SECTR1" || acronym == "SECTR2") {
    double degrees = 0.0;
    if (rawValue.ToDouble(&degrees)) {
      wxString label = acronym == "ORIENT" ? "Orientation" :
                       acronym == "SECTR1" ? "Sector start" : "Sector end";
      return label + ": " + wxString::Format("%g deg", degrees);
    }
  }

  return catalog.FormatAttributes(acronym + "=" + rawValue, nullptr);
}

static int CI_NavigationPriority(const wxString &acronym) {
  // 0: immediate safety state around the object.
  if (acronym == "WATLEV" || acronym == "EXPSOU" ||
      acronym == "QUASOU" || acronym == "RESTRN" ||
      acronym == "STATUS")
    return 0;

  // 1: what kind of object/mark/restriction it is.
  if (acronym.StartsWith("CAT") && acronym != "CATGEO") return 1;
  if (acronym == "FUNCTN" || acronym == "CONVIS" || acronym == "NATCON")
    return 1;

  // 2: lights, signals, bearings and ranges.
  if (acronym == "LITCHR" || acronym == "COLOUR" || acronym == "COLPAT" ||
      acronym == "SIGGRP" || acronym == "SIGPER" || acronym == "VALNMR" ||
      acronym == "ORIENT" || acronym == "SECTR1" || acronym == "SECTR2")
    return 2;

  // 3: clearances and physical dimensions.
  if (acronym == "HORCLR" || acronym == "HEIGHT" || acronym == "ELEVAT" ||
      acronym == "HORLEN" || acronym == "HORWID" || acronym == "VERLEN")
    return 3;

  // 4: operational text and validity periods.
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

  // A sounding/clearance is the most important single value and gets its own
  // prominent line directly below the object type.
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

  // Everything else shown by default must answer a navigation question:
  // danger/state, category, signal, clearance/dimension or operational note.
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
    if (!info.details.IsEmpty()) info.details = objectName + "\n" + info.details;
    else info.details = objectName;
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
        wxSize(360, 220),
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
              wxEXPAND | wxLEFT | wxRIGHT | wxTOP, 9);

    m_hoverInfoBody =
        new wxStaticText(m_hoverInfoWindow, wxID_ANY, wxEmptyString);
    root->Add(m_hoverInfoBody, 1, wxEXPAND | wxALL, 11);

    m_hoverInfoWindow->SetSizer(root);
    m_hoverInfoWindow->SetMinSize(wxSize(300, 160));

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
  m_hoverInfoTitle->SetLabel(title);

  const CI_NavigationInfo info = CI_BuildNavigationInfo(
      m_s57Catalog, feature, objectName, attributes, geometryType,
      m_showTechnicalData);

  m_hoverInfoMeta->SetLabel(info.primary);
  m_hoverInfoMeta->Show(!info.primary.IsEmpty());

  wxString body = info.details;
  if (m_showTechnicalData && !info.technical.IsEmpty()) {
    if (!body.IsEmpty()) body += "\n\n";
    body += "Technical\n" + info.technical;
  }
  m_hoverInfoBody->SetLabel(body);
  m_hoverInfoBody->Show(!body.IsEmpty());

  m_hoverInfoBody->Wrap(350);
  m_hoverInfoWindow->Layout();
  m_hoverInfoWindow->Fit();

  wxSize size = m_hoverInfoWindow->GetSize();
  size.SetWidth(std::max(320, std::min(440, size.GetWidth())));
  size.SetHeight(std::max(155, std::min(520, size.GetHeight())));
  m_hoverInfoWindow->SetSize(size);
  m_hoverInfoBody->Wrap(size.GetWidth() - 30);
  m_hoverInfoWindow->Layout();

  if (!m_hoverInfoWindow->IsShown()) m_hoverInfoWindow->Show();
}

]===])

string(SUBSTRING "${C}" 0 ${START} PRE)
string(SUBSTRING "${C}" ${END} -1 POST)
set(C "${PRE}${WINDOW_CODE}${POST}")

# Reuse the existing technical-data preference, but describe what it now does:
# the normal window is navigation-first; technical chart metadata is optional.
set(OLD_PREF "Show technical S-57 acronyms and raw values at the bottom of the card")
set(NEW_PREF "Show technical S-57 metadata (class, geometry, SCAMIN and source data)")
string(FIND "${C}" "${OLD_PREF}" PREF_POS)
if(NOT PREF_POS EQUAL -1)
  string(REPLACE "${OLD_PREF}" "${NEW_PREF}" C "${C}")
endif()

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed Chart Inspector navigation info v1")
message(STATUS "  object type is the clear primary heading")
message(STATUS "  soundings/clearances use OpenCPN user depth units")
message(STATUS "  navigation-relevant values are prioritized and decoded")
message(STATUS "  portrayal/source metadata is hidden by default")
message(STATUS "  existing technical-data preference reveals metadata at the bottom")
