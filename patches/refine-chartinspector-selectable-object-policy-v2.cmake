set(HDR "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.h")
set(CPP "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.cpp")
foreach(P "${HDR}" "${CPP}")
  if(NOT EXISTS "${P}")
    message(FATAL_ERROR "Missing ${P}")
  endif()
endforeach()

file(READ "${HDR}" H)
file(READ "${CPP}" C)

if(C MATCHES "CHARTINSPECTOR_SELECTABLE_POLICY_V2")
  message(STATUS "Chart Inspector selectable-object policy v2 already installed")
  return()
endif()

# HOVER_INFO marker lives in the header, while the detailed fallback marker
# lives in the implementation.
if(NOT H MATCHES "CHARTINSPECTOR_HOVER_INFO_V1")
  message(FATAL_ERROR "Live hover info v1 must be installed first")
endif()
if(NOT C MATCHES "CHARTINSPECTOR_DETAILED_HIDDEN_FALLBACK_V1")
  message(FATAL_ERROR "Detailed hidden fallback v1 must be installed first")
endif()

# -----------------------------------------------------------------------------
# Preference state: by default inspect only currently rendered objects. Hidden
# by scale (SCAMIN) can be enabled independently by the user.
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
# The Preferences class filter becomes authoritative for vector hover. Natural
# chart/background classes are absent from the default profile; physical and
# man-made objects are included. Users can change the exact set in Preferences.
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
// CHARTINSPECTOR_SELECTABLE_POLICY_V2
static bool CI_FeatureMatchesHoverFilter(const wxString &feature,
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
  if (!CI_FeatureMatchesHoverFilter(feature, best->includeFilter)) return true;
  const int score = CI_FeatureScore(feature, o->geometry_type);
]===])
string(FIND "${C}" "${COLLECT_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate CI_CollectHover feature block")
endif()
string(REPLACE "${COLLECT_OLD}" "${COLLECT_NEW}" C "${C}")

set(COPY_OLD [===[
  next.cursorLat = best->cursorLat; next.cursorLon = best->cursorLon;
  next.distanceMetres = distance;
]===])
set(COPY_NEW [===[
  next.cursorLat = best->cursorLat; next.cursorLon = best->cursorLon;
  next.distanceMetres = distance;
  next.includeFilter = best->includeFilter;
]===])
string(FIND "${C}" "${COPY_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate hover candidate copy block")
endif()
string(REPLACE "${COPY_OLD}" "${COPY_NEW}" C "${C}")

# -----------------------------------------------------------------------------
# Configuration and migration from the previous six-class default.
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
# Preferences UI.
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
  message(FATAL_ERROR "Could not locate Preferences application block")
endif()
string(REPLACE "${PREF_SAVE_OLD}" "${PREF_SAVE_NEW}" C "${C}")

# -----------------------------------------------------------------------------
# Query policy. Visible pass is always first. Hidden-by-scale fallback is opt-in.
# Both use the same user-selected class filter. Provider-side NoShow/display
# settings remain authoritative, so e.g. Anchor Info off still hides CBLSUB.
# -----------------------------------------------------------------------------
set(BEST_OLD [===[
  CI_HoverCandidate best;
  best.cursorLat = m_cursorLat;
  best.cursorLon = m_cursorLon;
  bool usedHiddenFallback = false;
]===])
set(BEST_NEW [===[
  CI_HoverCandidate best;
  best.cursorLat = m_cursorLat;
  best.cursorLon = m_cursorLon;
  best.includeFilter = m_featureFilter;
  bool usedHiddenFallback = false;
]===])
string(FIND "${C}" "${BEST_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate visible hover candidate initialization")
endif()
string(REPLACE "${BEST_OLD}" "${BEST_NEW}" C "${C}")

set(HIDDEN_OLD [===[
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
]===])
set(HIDDEN_NEW [===[
  if (m_includeScaleHidden && best.points.empty()) {
    CI_HoverCandidate hidden;
    hidden.cursorLat = m_cursorLat;
    hidden.cursorLon = m_cursorLon;
    hidden.includeFilter = m_featureFilter;
    q.flags = CI_SKIP_ATTRIBUTES | CI_INCLUDE_NON_RENDERED |
              CI_PREFER_DETAILED_CHART;
    queryFn(0, &q, CI_CollectHover, &hidden);
    if (!hidden.points.empty()) {
      best = hidden;
      usedHiddenFallback = true;
    }
  }
]===])
string(FIND "${C}" "${HIDDEN_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate detailed hidden fallback query block")
endif()
string(REPLACE "${HIDDEN_OLD}" "${HIDDEN_NEW}" C "${C}")

set(DETAIL_OLD [===[
      CI_HoverCandidate details;
      details.cursorLat = m_cursorLat;
      details.cursorLon = m_cursorLon;
      q.flags &= ~CI_SKIP_ATTRIBUTES;
      queryFn(0, &q,
              usedHiddenFallback ? CI_CollectHiddenNavigationHover
                                 : CI_CollectHover,
              &details);
]===])
set(DETAIL_NEW [===[
      CI_HoverCandidate details;
      details.cursorLat = m_cursorLat;
      details.cursorLon = m_cursorLon;
      details.includeFilter = m_featureFilter;
      q.flags &= ~CI_SKIP_ATTRIBUTES;
      queryFn(0, &q, CI_CollectHover, &details);
]===])
string(FIND "${C}" "${DETAIL_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate hover detail re-query block")
endif()
string(REPLACE "${DETAIL_OLD}" "${DETAIL_NEW}" C "${C}")

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed Chart Inspector selectable-object policy v2")
message(STATUS "  currently rendered objects are selected by default")
message(STATUS "  SCAMIN-hidden selection is optional and disabled by default")
message(STATUS "  Preferences feature classes are authoritative for all hover passes")
message(STATUS "  default profile favors physical/man-made objects")
message(STATUS "  natural/background chart geometry remains unselected by default")
