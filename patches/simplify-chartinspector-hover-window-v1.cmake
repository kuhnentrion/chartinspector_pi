set(HDR "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.h")
set(CPP "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.cpp")
foreach(P "${HDR}" "${CPP}")
  if(NOT EXISTS "${P}")
    message(FATAL_ERROR "Missing ${P}")
  endif()
endforeach()

file(READ "${HDR}" H)
file(READ "${CPP}" C)

if(C MATCHES "CHARTINSPECTOR_SIMPLE_HOVER_WINDOW_V1")
  message(STATUS "Chart Inspector simple hover window v1 already installed")
  return()
endif()

if(NOT H MATCHES "CHARTINSPECTOR_HOVER_INFO_V1")
  message(FATAL_ERROR "Live hover info v1 must be installed first")
endif()
if(NOT C MATCHES "CHARTINSPECTOR_FULL_HIGHLIGHT_GEOMETRY_V1")
  message(FATAL_ERROR "Full highlight geometry v1 must be installed first")
endif()

# -----------------------------------------------------------------------------
# Header: keep the existing method names to minimize churn, but turn the old
# canvas child panel into one small floating tool window.
# -----------------------------------------------------------------------------
set(H_OLD [===[
  wxPanel *m_hoverInfoPanel = nullptr;
  wxStaticText *m_hoverInfoTitle = nullptr;
  wxStaticText *m_hoverInfoMeta = nullptr;
  wxStaticText *m_hoverInfoBody = nullptr;
]===])
set(H_NEW [===[
  wxFrame *m_hoverInfoWindow = nullptr;
  wxStaticText *m_hoverInfoTitle = nullptr;
  wxStaticText *m_hoverInfoMeta = nullptr;
  wxStaticText *m_hoverInfoBody = nullptr;
]===])
string(FIND "${H}" "${H_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate hover info window fields")
endif()
string(REPLACE "${H_OLD}" "${H_NEW}" H "${H}")
file(WRITE "${HDR}" "${H}")

# -----------------------------------------------------------------------------
# Replace the old lower-right canvas card implementation. The new window is a
# normal movable wxFrame tool window. It appears when a hover target exists and
# hides when there is none. Closing it just hides it; the next hovered object
# brings it back. No docking, buttons, tabs or duplicated click UI.
# -----------------------------------------------------------------------------
set(START_MARK "void ChartInspectorPi::HideHoverInfoPanel() {")
set(END_MARK "void ChartInspectorPi::ClearHoverGeometry() {")
string(FIND "${C}" "${START_MARK}" START)
string(FIND "${C}" "${END_MARK}" END)
if(START EQUAL -1 OR END EQUAL -1 OR END LESS START)
  message(FATAL_ERROR "Could not locate existing hover info implementation")
endif()

set(WINDOW_CODE [===[
// CHARTINSPECTOR_SIMPLE_HOVER_WINDOW_V1
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
        wxSize(360, 260),
        wxCAPTION | wxCLOSE_BOX | wxRESIZE_BORDER | wxFRAME_TOOL_WINDOW |
            wxSTAY_ON_TOP);

    wxBoxSizer *root = new wxBoxSizer(wxVERTICAL);

    m_hoverInfoTitle =
        new wxStaticText(m_hoverInfoWindow, wxID_ANY, wxEmptyString);
    wxFont titleFont = m_hoverInfoTitle->GetFont();
    titleFont.SetWeight(wxFONTWEIGHT_BOLD);
    titleFont.SetPointSize(titleFont.GetPointSize() + 1);
    m_hoverInfoTitle->SetFont(titleFont);
    root->Add(m_hoverInfoTitle, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP, 10);

    m_hoverInfoMeta =
        new wxStaticText(m_hoverInfoWindow, wxID_ANY, wxEmptyString);
    root->Add(m_hoverInfoMeta, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP, 5);

    root->Add(new wxStaticLine(m_hoverInfoWindow), 0,
              wxEXPAND | wxLEFT | wxRIGHT | wxTOP, 8);

    m_hoverInfoBody =
        new wxStaticText(m_hoverInfoWindow, wxID_ANY, wxEmptyString);
    root->Add(m_hoverInfoBody, 1, wxEXPAND | wxALL, 10);

    m_hoverInfoWindow->SetSizer(root);
    m_hoverInfoWindow->SetMinSize(wxSize(300, 180));

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

  const wxString geometry = geometryType == 3 ? "Area" :
                            geometryType == 2 ? "Line" : "Point";
  wxString meta = "S-57: " + feature + "  -  " + geometry;
  if (!objectName.IsEmpty()) meta += "\n" + objectName;
  m_hoverInfoMeta->SetLabel(meta);

  wxString technical;
  wxString body = m_s57Catalog.FormatAttributes(attributes, &technical);
  if (body.IsEmpty() && !attributes.IsEmpty()) body = attributes;
  if (m_showTechnicalData && !technical.IsEmpty()) {
    if (!body.IsEmpty()) body += "\n";
    body += technical;
  }
  if (body.IsEmpty()) body = "No attributes";

  // Keep the live window readable. The full raw object dump is deliberately
  // not duplicated here; this is a concise answer to "what is that?".
  wxString compact;
  wxStringTokenizer lines(body, "\n", wxTOKEN_STRTOK);
  int lineCount = 0;
  while (lines.HasMoreTokens() && lineCount < 14) {
    wxString line = lines.GetNextToken();
    line.Trim(true);
    line.Trim(false);
    if (line.IsEmpty()) continue;
    if (!compact.IsEmpty()) compact += "\n";
    compact += line;
    ++lineCount;
  }
  if (lines.HasMoreTokens()) compact += "\n...";

  m_hoverInfoBody->SetLabel(compact);
  m_hoverInfoBody->Wrap(330);
  m_hoverInfoWindow->Layout();
  m_hoverInfoWindow->Fit();

  wxSize size = m_hoverInfoWindow->GetSize();
  size.SetWidth(std::max(320, std::min(430, size.GetWidth())));
  size.SetHeight(std::max(190, std::min(520, size.GetHeight())));
  m_hoverInfoWindow->SetSize(size);
  m_hoverInfoBody->Wrap(size.GetWidth() - 28);
  m_hoverInfoWindow->Layout();

  if (!m_hoverInfoWindow->IsShown()) m_hoverInfoWindow->Show();
}

]===])

string(SUBSTRING "${C}" 0 ${START} PRE)
string(SUBSTRING "${C}" ${END} -1 POST)
set(C "${PRE}${WINDOW_CODE}${POST}")

# -----------------------------------------------------------------------------
# Shutdown cleanup: replace the old canvas-panel member with the floating frame.
# -----------------------------------------------------------------------------
set(CLEAN_OLD [===[
  if (m_hoverInfoPanel) m_hoverInfoPanel->Destroy();
  m_hoverInfoPanel = nullptr;
  m_hoverInfoTitle = nullptr;
  m_hoverInfoMeta = nullptr;
  m_hoverInfoBody = nullptr;
]===])
set(CLEAN_NEW [===[
  if (m_hoverInfoWindow) m_hoverInfoWindow->Destroy();
  m_hoverInfoWindow = nullptr;
  m_hoverInfoTitle = nullptr;
  m_hoverInfoMeta = nullptr;
  m_hoverInfoBody = nullptr;
]===])
string(FIND "${C}" "${CLEAN_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate hover info shutdown cleanup")
endif()
string(REPLACE "${CLEAN_OLD}" "${CLEAN_NEW}" C "${C}")

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed Chart Inspector simple floating hover window v1")
message(STATUS "  one movable Chart Inspector tool window")
message(STATUS "  shows exactly the currently highlighted object")
message(STATUS "  title, S-57 class/geometry, name and concise attributes")
message(STATUS "  no docking, tabs, buttons or duplicate hover card")
