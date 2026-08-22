set(HDR "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.h")
set(CPP "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.cpp")
foreach(P "${HDR}" "${CPP}")
  if(NOT EXISTS "${P}")
    message(FATAL_ERROR "Missing ${P}")
  endif()
endforeach()

file(READ "${HDR}" H)
file(READ "${CPP}" C)

if(C MATCHES "CHARTINSPECTOR_HOVER_INFO_V1")
  message(STATUS "Chart Inspector live hover info v1 already installed")
  return()
endif()

if(NOT C MATCHES "CHARTINSPECTOR_VECTOR_HOVER_V1")
  message(FATAL_ERROR "Vector hover highlight v1 must be installed first")
endif()
if(NOT C MATCHES "CHARTINSPECTOR_HOVER_NEAREST_V1")
  message(FATAL_ERROR "Nearest-geometry hover ranking v1 must be installed first")
endif()
if(NOT C MATCHES "CHARTINSPECTOR_DETAILED_HIDDEN_FALLBACK_V1")
  message(FATAL_ERROR "Detailed hidden hover fallback v1 must be installed first")
endif()

# -----------------------------------------------------------------------------
# Header: add a lightweight, automatically updated hover information card.
# The existing click card remains unchanged and can still be used for the full
# visual summary.  This card describes exactly the geometry selected by the
# vector hover query, including hidden/detailed-chart fallback objects.
# -----------------------------------------------------------------------------
set(H_METHOD_OLD [===[
  void UpdateHoverGeometry(bool force = false);
  void QueryAssociatedLight();
]===])
set(H_METHOD_NEW [===[
  void UpdateHoverGeometry(bool force = false);
  void UpdateHoverInfoPanel(const wxString &feature,
                            const wxString &objectName,
                            const wxString &attributes, int geometryType);
  void HideHoverInfoPanel();
  void QueryAssociatedLight();
]===])
string(FIND "${H}" "${H_METHOD_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate hover method declarations in ${HDR}")
endif()
string(REPLACE "${H_METHOD_OLD}" "${H_METHOD_NEW}" H "${H}")

set(H_FIELDS_OLD [===[
  wxString m_hoverFeature;
  bool m_hasHoverGeometry = false;

  wxPanel *m_infoPanel = nullptr;
]===])
set(H_FIELDS_NEW [===[
  wxString m_hoverFeature;
  bool m_hasHoverGeometry = false;

  // CHARTINSPECTOR_HOVER_INFO_V1
  wxPanel *m_hoverInfoPanel = nullptr;
  wxStaticText *m_hoverInfoTitle = nullptr;
  wxStaticText *m_hoverInfoMeta = nullptr;
  wxStaticText *m_hoverInfoBody = nullptr;
  wxString m_hoverInfoKey;

  wxPanel *m_infoPanel = nullptr;
]===])
string(FIND "${H}" "${H_FIELDS_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate hover member fields in ${HDR}")
endif()
string(REPLACE "${H_FIELDS_OLD}" "${H_FIELDS_NEW}" H "${H}")
file(WRITE "${HDR}" "${H}")

# -----------------------------------------------------------------------------
# Hover candidate: retain object name and attributes when a query requests
# them. The fast geometry pass still uses SKIP_ATTRIBUTES, so this has zero
# extra provider work until the highlighted object actually changes.
# -----------------------------------------------------------------------------
set(CAND_OLD [===[
  double cursorLon = 0.0;
  double distanceMetres = 1.0e100;
};
]===])
set(CAND_NEW [===[
  double cursorLon = 0.0;
  double distanceMetres = 1.0e100;
  wxString objectName;
  wxString attributes;
};
]===])
string(FIND "${C}" "${CAND_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate current CI_HoverCandidate tail")
endif()
string(REPLACE "${CAND_OLD}" "${CAND_NEW}" C "${C}")

set(COPY_OLD [===[
  next.geometry = o->geometry_type; next.feature = feature; next.score = score;
  next.cursorLat = best->cursorLat; next.cursorLon = best->cursorLon;
  next.distanceMetres = distance;
]===])
set(COPY_NEW [===[
  next.geometry = o->geometry_type; next.feature = feature; next.score = score;
  next.cursorLat = best->cursorLat; next.cursorLon = best->cursorLon;
  next.distanceMetres = distance;
  next.objectName =
      wxString::FromUTF8(o->object_name_utf8 ? o->object_name_utf8 : "");
  for (uint32_t i = 0; o->attributes && i < o->attribute_count; ++i) {
    const char *name = o->attributes[i].name_utf8;
    const char *value = o->attributes[i].value_utf8;
    if (!name || !*name) continue;
    if (!next.attributes.IsEmpty()) next.attributes += "\n";
    next.attributes += wxString::FromUTF8(name);
    next.attributes += "=";
    next.attributes += wxString::FromUTF8(value ? value : "");
  }
]===])
string(FIND "${C}" "${COPY_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate CI_CollectHover candidate copy block")
endif()
string(REPLACE "${COPY_OLD}" "${COPY_NEW}" C "${C}")

# -----------------------------------------------------------------------------
# Small fixed hover card. It is intentionally not attached to the mouse cursor,
# avoiding feedback/flicker when the panel itself would otherwise intercept
# mouse events.  It sits at the lower right of the canvas and disappears when
# no vector hover target exists.
# -----------------------------------------------------------------------------
set(CLEAR_ANCHOR [===[
void ChartInspectorPi::ClearHoverGeometry() {
]===])
set(INFO_CODE [===[
void ChartInspectorPi::HideHoverInfoPanel() {
  m_hoverInfoKey.clear();
  if (m_hoverInfoPanel) m_hoverInfoPanel->Hide();
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

  if (!m_hoverInfoPanel) {
    m_hoverInfoPanel = new wxPanel(canvas, wxID_ANY, wxDefaultPosition,
                                  wxDefaultSize, wxBORDER_SIMPLE);
    wxBoxSizer *root = new wxBoxSizer(wxVERTICAL);
    m_hoverInfoTitle =
        new wxStaticText(m_hoverInfoPanel, wxID_ANY, wxEmptyString);
    wxFont titleFont = m_hoverInfoTitle->GetFont();
    titleFont.SetWeight(wxFONTWEIGHT_BOLD);
    m_hoverInfoTitle->SetFont(titleFont);
    root->Add(m_hoverInfoTitle, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP, 9);

    m_hoverInfoMeta =
        new wxStaticText(m_hoverInfoPanel, wxID_ANY, wxEmptyString);
    wxFont metaFont = m_hoverInfoMeta->GetFont();
    metaFont.SetPointSize(std::max(7, metaFont.GetPointSize() - 1));
    m_hoverInfoMeta->SetFont(metaFont);
    root->Add(m_hoverInfoMeta, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP, 5);

    m_hoverInfoBody =
        new wxStaticText(m_hoverInfoPanel, wxID_ANY, wxEmptyString);
    root->Add(m_hoverInfoBody, 0, wxEXPAND | wxALL, 9);
    m_hoverInfoPanel->SetSizer(root);
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
  if (body.IsEmpty()) body = "No attributes returned";

  // Keep the hover card compact even for attribute-heavy S-57 objects.
  wxString compact;
  wxStringTokenizer lines(body, "\n", wxTOKEN_STRTOK);
  int lineCount = 0;
  while (lines.HasMoreTokens() && lineCount < 10) {
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
  m_hoverInfoBody->Wrap(310);

  wxColour background = wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOW);
  wxColour foreground = wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOWTEXT);
  wxColour secondary = wxSystemSettings::GetColour(wxSYS_COLOUR_GRAYTEXT);
  GetGlobalColor("DILG0", &background);
  GetGlobalColor("DILG4", &foreground);
  GetGlobalColor("DILG3", &secondary);
  m_hoverInfoPanel->SetBackgroundColour(background);
  m_hoverInfoPanel->SetForegroundColour(foreground);
  m_hoverInfoTitle->SetForegroundColour(foreground);
  m_hoverInfoMeta->SetForegroundColour(secondary);
  m_hoverInfoBody->SetForegroundColour(foreground);

  m_hoverInfoPanel->Layout();
  m_hoverInfoPanel->Fit();
  wxSize size = m_hoverInfoPanel->GetSize();
  size.SetWidth(std::max(280, std::min(350, size.GetWidth())));
  m_hoverInfoPanel->SetSize(size);
  m_hoverInfoPanel->Layout();

  const wxSize canvasSize = canvas->GetClientSize();
  m_hoverInfoPanel->Move(
      std::max(12, canvasSize.GetWidth() - size.GetWidth() - 14),
      std::max(12, canvasSize.GetHeight() - size.GetHeight() - 14));
  m_hoverInfoPanel->Show();
  m_hoverInfoPanel->Raise();
}

void ChartInspectorPi::ClearHoverGeometry() {
]===])
string(FIND "${C}" "${CLEAR_ANCHOR}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate ClearHoverGeometry definition")
endif()
string(REPLACE "${CLEAR_ANCHOR}" "${INFO_CODE}" C "${C}")

set(CLEAR_BODY_OLD [===[
  m_hoverPoints.clear(); m_hoverParts.clear(); m_hoverFeature.clear();
  m_hoverGeometryType = 0; m_hasHoverGeometry = false;
}
]===])
set(CLEAR_BODY_NEW [===[
  m_hoverPoints.clear(); m_hoverParts.clear(); m_hoverFeature.clear();
  m_hoverGeometryType = 0; m_hasHoverGeometry = false;
  HideHoverInfoPanel();
}
]===])
string(FIND "${C}" "${CLEAR_BODY_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate ClearHoverGeometry body")
endif()
string(REPLACE "${CLEAR_BODY_OLD}" "${CLEAR_BODY_NEW}" C "${C}")

# -----------------------------------------------------------------------------
# Two-pass hover query: geometry remains cheap. When the selected target changes
# we immediately repeat the same query with SKIP_ATTRIBUTES cleared and use the
# same candidate ranking/sink. This guarantees the card describes the exact
# object which is highlighted, rather than a separate legacy hit-test result.
# -----------------------------------------------------------------------------
set(QUERY_OLD [===[
  CI_HoverCandidate best;
  best.cursorLat = m_cursorLat;
  best.cursorLon = m_cursorLon;

  // Pass 1: only objects which the active chart currently renders.
  queryFn(0, &q, CI_CollectHover, &best);

  // Pass 2: if the visible pass is empty, look for useful navigation objects
  // which are hidden by portrayal or live in a more detailed cached ENC cell.
  // The dedicated sink deliberately rejects generic hidden lines/areas.
  if (best.points.empty()) {
    CI_HoverCandidate hidden;
    hidden.cursorLat = m_cursorLat;
    hidden.cursorLon = m_cursorLon;
    q.flags = CI_SKIP_ATTRIBUTES | CI_INCLUDE_NON_RENDERED |
              CI_PREFER_DETAILED_CHART;
    queryFn(0, &q, CI_CollectHiddenNavigationHover, &hidden);
    if (!hidden.points.empty()) best = hidden;
  }

  m_lastHoverQueryMs = now; m_lastHoverQueryPosition = m_mousePosition;
]===])
set(QUERY_NEW [===[
  CI_HoverCandidate best;
  best.cursorLat = m_cursorLat;
  best.cursorLon = m_cursorLon;
  bool usedHiddenFallback = false;

  // Pass 1: only objects which the active chart currently renders.
  queryFn(0, &q, CI_CollectHover, &best);

  // Pass 2: if the visible pass is empty, look for useful navigation objects
  // which are hidden by portrayal or live in a more detailed cached ENC cell.
  // The dedicated sink deliberately rejects generic hidden lines/areas.
  if (best.points.empty()) {
    CI_HoverCandidate hidden;
    hidden.cursorLat = m_cursorLat;
    hidden.cursorLon = m_cursorLon;
    q.flags = CI_SKIP_ATTRIBUTES | CI_INCLUDE_NON_RENDERED |
              CI_PREFER_DETAILED_CHART;
    queryFn(0, &q, CI_CollectHiddenNavigationHover, &hidden);
    if (!hidden.points.empty()) {
      best = hidden;
      usedHiddenFallback = true;
    }
  }

  if (!best.points.empty()) {
    const wxString key =
        best.feature + "|" + wxString::Format("%u|%.8f|%.8f", best.geometry,
                                               best.points[0].lat,
                                               best.points[0].lon);
    if (key != m_hoverInfoKey) {
      CI_HoverCandidate details;
      details.cursorLat = m_cursorLat;
      details.cursorLon = m_cursorLon;
      q.flags &= ~CI_SKIP_ATTRIBUTES;
      queryFn(0, &q,
              usedHiddenFallback ? CI_CollectHiddenNavigationHover
                                 : CI_CollectHover,
              &details);
      if (!details.points.empty()) {
        UpdateHoverInfoPanel(details.feature, details.objectName,
                             details.attributes,
                             static_cast<int>(details.geometry));
        m_hoverInfoKey = key;
      } else {
        HideHoverInfoPanel();
      }
    }
  }

  m_lastHoverQueryMs = now; m_lastHoverQueryPosition = m_mousePosition;
]===])
string(FIND "${C}" "${QUERY_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate detailed two-pass hover query block")
endif()
string(REPLACE "${QUERY_OLD}" "${QUERY_NEW}" C "${C}")

# -----------------------------------------------------------------------------
# Lifetime: the hover card is a separate canvas child from the existing click
# information card, so clean it up explicitly at plugin shutdown.
# -----------------------------------------------------------------------------
set(DEINIT_OLD [===[
  if (m_infoPanel) m_infoPanel->Destroy();
  m_infoPanel = nullptr;
  return true;
]===])
set(DEINIT_NEW [===[
  if (m_infoPanel) m_infoPanel->Destroy();
  m_infoPanel = nullptr;
  if (m_hoverInfoPanel) m_hoverInfoPanel->Destroy();
  m_hoverInfoPanel = nullptr;
  m_hoverInfoTitle = nullptr;
  m_hoverInfoMeta = nullptr;
  m_hoverInfoBody = nullptr;
  return true;
]===])
string(FIND "${C}" "${DEINIT_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate DeInit info-panel cleanup block")
endif()
string(REPLACE "${DEINIT_OLD}" "${DEINIT_NEW}" C "${C}")

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed Chart Inspector live hover metadata panel v1")
message(STATUS "  fixed lower-right card follows the exact cyan hover target")
message(STATUS "  feature class, geometry, object name and S-57 attributes shown")
message(STATUS "  attribute query runs only when the selected hover object changes")
message(STATUS "  existing full click information card remains unchanged")
