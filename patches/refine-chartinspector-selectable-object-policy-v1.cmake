set(HDR "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.h")
set(CPP "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.cpp")
foreach(P "${HDR}" "${CPP}")
  if(NOT EXISTS "${P}")
    message(FATAL_ERROR "Missing ${P}")
  endif()
endforeach()

file(READ "${HDR}" H)
file(READ "${CPP}" C)

if(C MATCHES "CHARTINSPECTOR_SELECTABLE_POLICY_V1")
  message(STATUS "Chart Inspector selectable-object policy v1 already installed")
  return()
endif()

if(NOT C MATCHES "CHARTINSPECTOR_HOVER_INFO_V1")
  message(FATAL_ERROR "Live hover info v1 must be installed first")
endif()
if(NOT C MATCHES "CHARTINSPECTOR_DETAILED_HIDDEN_FALLBACK_V1")
  message(FATAL_ERROR "Detailed hidden fallback v1 must be installed first")
endif()

# -----------------------------------------------------------------------------
# Header: hidden-by-scale querying becomes an explicit user preference. Visible
# objects remain the default and preferred interaction model.
# -----------------------------------------------------------------------------
set(H_OLD [===[
  bool m_showTechnicalData = false;
  int m_hitRadiusPixels = 5;
  wxString m_featureFilter = "BOY*,BCN*,LIGHTS,WRECKS,UWTROC,OBSTRN";
]===])
set(H_NEW [===[
  bool m_showTechnicalData = false;
  bool m_includeScaleHidden = false;
  int m_hitRadiusPixels = 5;
  wxString m_featureFilter = "BOY*,BCN*,LIGHTS,TOPMAR,DAYMAR,WRECKS,UWTROC,OBSTRN,LNDMRK,BUISGL,SILTNK,BRIDGE,CRANES,FLODOC,GATCON,DAMCON,HRBFAC,BERTHS,MORFAC,OFSPLF,PILPNT,CBLSUB,PIPARE,PIPSOL,TUNNEL,RTPBCN,RADSTA,RSCSTA,FORSTC,CAUSWY,DYKCON";
]===])
string(FIND "${H}" "${H_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate Chart Inspector preference fields")
endif()
string(REPLACE "${H_OLD}" "${H_NEW}" H "${H}")
file(WRITE "${HDR}" "${H}")

# -----------------------------------------------------------------------------
# Hover sink: make the existing Preferences feature-class checklist authoritative
# for the vector geometry hover path. Until now the legacy click query used the
# filter, but QueryVectorChartObjectsV1 could still highlight other classes.
# -----------------------------------------------------------------------------
set(CAND_OLD [===[
  double distanceMetres = 1.0e100;
  wxString objectName;
  wxString attributes;
};
]===])
set(CAND_NEW [===[
  double distanceMetres = 1.0e100;
  wxString objectName;
  wxString attributes;
  wxString includeFilter;
};
]===])
string(FIND "${C}" "${CAND_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate current hover candidate fields")
endif()
string(REPLACE "${CAND_OLD}" "${CAND_NEW}" C "${C}")

set(SCORE_ANCHOR [===[
int CI_FeatureScore(const wxString &f, uint32_t geometry) {
]===])
set(SCORE_NEW [===[
// CHARTINSPECTOR_SELECTABLE_POLICY_V1
static bool CI_FeatureMatchesFilter(const wxString &feature,
                                    const wxString &filter) {
  if (feature.IsEmpty() || filter.IsEmpty()) return false;
  const wxString candidate = feature.Upper();
  wxStringTokenizer tokens(filter, ",; \t\r\n", wxTOKEN_STRTOK);
  while (tokens.HasMoreTokens()) {
    wxString token = tokens.GetNextToken().Upper();
    token.Trim(true);
    token.Trim(false);
    if (token.IsEmpty()) continue;
    if (token.EndsWith("*")) {
      token.RemoveLast();
      if (!token.IsEmpty() && candidate.StartsWith(token)) return true;
    } else if (candidate == token) {
      return true;
    }
  }
  return false;
}

int CI_FeatureScore(const wxString &f, uint32_t geometry) {
]===])
string(FIND "${C}" "${SCORE_ANCHOR}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate CI_FeatureScore")
endif()
string(REPLACE "${SCORE_ANCHOR}" "${SCORE_NEW}" C "${C}")

set(COLLECT_OLD [===[
  const wxString feature = wxString::FromUTF8(o->feature_class_utf8 ? o->feature_class_utf8 : "").Upper();
  const int score = CI_FeatureScore(feature, o->geometry_type);
]===])
set(COLLECT_NEW [===[
  const wxString feature = wxString::FromUTF8(o->feature_class_utf8 ? o->feature_class_utf8 : "").Upper();
  if (!CI_FeatureMatchesFilter(feature, best->includeFilter)) return true;
  const int score = CI_FeatureScore(feature, o->geometry_type);
]===])
string(FIND "${C}" "${COLLECT_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate CI_CollectHover feature block")
endif()
string(REPLACE "${COLLECT_OLD}" "${COLLECT_NEW}" C "${C}")

set(COPY_FILTER_OLD [===[
  next.cursorLat = best->cursorLat; next.cursorLon = best->cursorLon;
  next.distanceMetres = distance;
]===])
set(COPY_FILTER_NEW [===[
  next.cursorLat = best->cursorLat; next.cursorLon = best->cursorLon;
  next.distanceMetres = distance;
  next.includeFilter = best->includeFilter;
]===])
string(FIND "${C}" "${COPY_FILTER_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate hover candidate cursor copy block")
endif()
string(REPLACE "${COPY_FILTER_OLD}" "${COPY_FILTER_NEW}" C "${C}")

# -----------------------------------------------------------------------------
# Config: migrate the original tiny default filter to the broader physical /
# man-made navigation-object profile. Existing customized filters are preserved.
# Hidden-by-scale selection is off by default.
# -----------------------------------------------------------------------------
set(LOAD_OLD [===[
  m_config->Read("ShowTechnicalData", &m_showTechnicalData, false);
  long radius = 5;
  m_config->Read("HitRadiusPixels", &radius, 5L);
  m_hitRadiusPixels = static_cast<int>(std::max(2L, std::min(20L, radius)));
  m_config->Read("FeatureFilter", &m_featureFilter,
                 "BOY*,BCN*,LIGHTS,WRECKS,UWTROC,OBSTRN");
]===])
set(LOAD_NEW [===[
  m_config->Read("ShowTechnicalData", &m_showTechnicalData, false);
  m_config->Read("IncludeScaleHidden", &m_includeScaleHidden, false);
  long radius = 5;
  m_config->Read("HitRadiusPixels", &radius, 5L);
  m_hitRadiusPixels = static_cast<int>(std::max(2L, std::min(20L, radius)));
  const wxString defaultSelectable =
      "BOY*,BCN*,LIGHTS,TOPMAR,DAYMAR,WRECKS,UWTROC,OBSTRN,LNDMRK,"
      "BUISGL,SILTNK,BRIDGE,CRANES,FLODOC,GATCON,DAMCON,HRBFAC,BERTHS,"
      "MORFAC,OFSPLF,PILPNT,CBLSUB,PIPARE,PIPSOL,TUNNEL,RTPBCN,RADSTA,"
      "RSCSTA,FORSTC,CAUSWY,DYKCON";
  m_config->Read("FeatureFilter", &m_featureFilter, defaultSelectable);
  if (m_featureFilter == "BOY*,BCN*,LIGHTS,WRECKS,UWTROC,OBSTRN")
    m_featureFilter = defaultSelectable;
]===])
string(FIND "${C}" "${LOAD_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate LoadConfig hover preferences")
endif()
string(REPLACE "${LOAD_OLD}" "${LOAD_NEW}" C "${C}")

set(SAVE_OLD [===[
  m_config->Write("ShowTechnicalData", m_showTechnicalData);
  m_config->Write("HitRadiusPixels", static_cast<long>(m_hitRadiusPixels));
]===])
set(SAVE_NEW [===[
  m_config->Write("ShowTechnicalData", m_showTechnicalData);
  m_config->Write("IncludeScaleHidden", m_includeScaleHidden);
  m_config->Write("HitRadiusPixels", static_cast<long>(m_hitRadiusPixels));
]===])
string(FIND "${C}" "${SAVE_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate SaveConfig hover preferences")
endif()
string(REPLACE "${SAVE_OLD}" "${SAVE_NEW}" C "${C}")

# -----------------------------------------------------------------------------
# Preferences UI: expose scale-hidden behavior independently from class choice.
# The class checklist already gives exact per-feature control.
# -----------------------------------------------------------------------------
set(PREF_OLD [===[
  wxCheckBox *technical = new wxCheckBox(
      &dialog, wxID_ANY,
      "Show technical S-57 acronyms and raw values at the bottom of the card");
]===])
set(PREF_NEW [===[
  wxCheckBox *scaleHidden = new wxCheckBox(
      &dialog, wxID_ANY,
      "Also inspect selected objects hidden only by chart scale (SCAMIN)");
  scaleHidden->SetValue(m_includeScaleHidden);
  root->Add(scaleHidden, 0, wxLEFT | wxRIGHT | wxBOTTOM, 10);

  wxCheckBox *technical = new wxCheckBox(
      &dialog, wxID_ANY,
      "Show technical S-57 acronyms and raw values at the bottom of the card");
]===])
string(FIND "${C}" "${PREF_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate Preferences technical checkbox")
endif()
string(REPLACE "${PREF_OLD}" "${PREF_NEW}" C "${C}")

set(PREF_SAVE_OLD [===[
    m_showTechnicalData = technical->GetValue();
    wxString filterValue;
]===])
set(PREF_SAVE_NEW [===[
    m_showTechnicalData = technical->GetValue();
    m_includeScaleHidden = scaleHidden->GetValue();
    wxString filterValue;
]===])
string(FIND "${C}" "${PREF_SAVE_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate Preferences value application block")
endif()
string(REPLACE "${PREF_SAVE_OLD}" "${PREF_SAVE_NEW}" C "${C}")

# -----------------------------------------------------------------------------
# Vector hover query: visible objects first and by default only. The optional
# hidden-scale pass is executed only when explicitly enabled. All three query
# candidates (visible, hidden, detail reload) use the Preferences class filter.
# -----------------------------------------------------------------------------
set(BEST_INIT_OLD [===[
  CI_HoverCandidate best;
  best.cursorLat = m_cursorLat;
  best.cursorLon = m_cursorLon;
  bool usedHiddenFallback = false;
]===])
set(BEST_INIT_NEW [===[
  CI_HoverCandidate best;
  best.cursorLat = m_cursorLat;
  best.cursorLon = m_cursorLon;
  best.includeFilter = m_featureFilter;
  bool usedHiddenFallback = false;
]===])
string(FIND "${C}" "${BEST_INIT_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate visible hover candidate initialization")
endif()
string(REPLACE "${BEST_INIT_OLD}" "${BEST_INIT_NEW}" C "${C}")

set(HIDDEN_IF_OLD [===[
  if (best.points.empty()) {
    CI_HoverCandidate hidden;
    hidden.cursorLat = m_cursorLat;
    hidden.cursorLon = m_cursorLon;
]===])
set(HIDDEN_IF_NEW [===[
  if (m_includeScaleHidden && best.points.empty()) {
    CI_HoverCandidate hidden;
    hidden.cursorLat = m_cursorLat;
    hidden.cursorLon = m_cursorLon;
    hidden.includeFilter = m_featureFilter;
]===])
string(FIND "${C}" "${HIDDEN_IF_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate hidden hover fallback block")
endif()
string(REPLACE "${HIDDEN_IF_OLD}" "${HIDDEN_IF_NEW}" C "${C}")

set(DETAIL_OLD [===[
      CI_HoverCandidate details;
      details.cursorLat = m_cursorLat;
      details.cursorLon = m_cursorLon;
      q.flags &= ~CI_SKIP_ATTRIBUTES;
]===])
set(DETAIL_NEW [===[
      CI_HoverCandidate details;
      details.cursorLat = m_cursorLat;
      details.cursorLon = m_cursorLon;
      details.includeFilter = m_featureFilter;
      q.flags &= ~CI_SKIP_ATTRIBUTES;
]===])
string(FIND "${C}" "${DETAIL_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate hover detail candidate initialization")
endif()
string(REPLACE "${DETAIL_OLD}" "${DETAIL_NEW}" C "${C}")

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed Chart Inspector selectable-object policy v1")
message(STATUS "  currently rendered objects are the default hover targets")
message(STATUS "  SCAMIN-hidden objects are optional and disabled by default")
message(STATUS "  Preferences feature-class checklist now controls vector hover")
message(STATUS "  default profile favors physical/man-made navigation objects")
message(STATUS "  natural/background chart geometry remains unselected by default")
