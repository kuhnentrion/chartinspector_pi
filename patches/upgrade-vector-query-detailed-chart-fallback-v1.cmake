if(NOT DEFINED OPENCPN_ROOT)
  message(FATAL_ERROR "OPENCPN_ROOT is required, e.g. -DOPENCPN_ROOT=C:/Users/Johannes/source/OpenCPN")
endif()

file(TO_CMAKE_PATH "${OPENCPN_ROOT}" OPENCPN_ROOT)
set(OPENCPN_API "${OPENCPN_ROOT}/include/ocpn_plugin.h")
set(OPENCPN_CPP "${OPENCPN_ROOT}/gui/src/ocpn_plugin_gui.cpp")
set(INSPECTOR_CPP "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.cpp")

foreach(P "${OPENCPN_API}" "${OPENCPN_CPP}" "${INSPECTOR_CPP}")
  if(NOT EXISTS "${P}")
    message(FATAL_ERROR "Required file not found: ${P}")
  endif()
endforeach()

# -----------------------------------------------------------------------------
# Host-side chart selection flag.
#
# The normal QueryVectorChartObjectsV1 path intentionally queries the chart
# currently used by the canvas at the cursor position.  At small scales the
# quilt may switch to a smaller-scale ENC cell, so detailed objects such as
# buoys can disappear from the queried dataset completely.  This flag asks the
# host to prefer the largest-scale *cached* vector chart covering the cursor.
# It never loads a new chart during mouse hover.
# -----------------------------------------------------------------------------
file(READ "${OPENCPN_API}" H)
if(NOT H MATCHES "PI_VECTOR_QUERY_PREFER_DETAILED_CHART_V1")
  set(FLAGS_OLD [===[
enum PI_VectorQueryFlagsV1 : uint32_t {
  PI_VECTOR_QUERY_SKIP_ATTRIBUTES_V1       = 1u << 0,
  PI_VECTOR_QUERY_INCLUDE_NON_RENDERED_V1 = 1u << 1
};
]===])
  set(FLAGS_NEW [===[
enum PI_VectorQueryFlagsV1 : uint32_t {
  PI_VECTOR_QUERY_SKIP_ATTRIBUTES_V1        = 1u << 0,
  PI_VECTOR_QUERY_INCLUDE_NON_RENDERED_V1   = 1u << 1,
  PI_VECTOR_QUERY_PREFER_DETAILED_CHART_V1  = 1u << 2
};
]===])
  string(FIND "${H}" "${FLAGS_OLD}" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate current PI_VectorQueryFlagsV1 in ${OPENCPN_API}")
  endif()
  string(REPLACE "${FLAGS_OLD}" "${FLAGS_NEW}" H "${H}")
  file(WRITE "${OPENCPN_API}" "${H}")
  message(STATUS "Added PI_VECTOR_QUERY_PREFER_DETAILED_CHART_V1 to OpenCPN API")
else()
  message(STATUS "Detailed-chart query flag already present in OpenCPN API")
endif()

# -----------------------------------------------------------------------------
# OpenCPN host: before using the currently rendered quilt chart, optionally
# choose the most detailed vector chart at the query position which is already
# in ChartData's cache. ChartStack::AddChart sorts entries by chart scale, with
# the smallest denominator (largest scale / most detailed chart) first.
# -----------------------------------------------------------------------------
file(READ "${OPENCPN_CPP}" C)
if(NOT C MATCHES "VECTOR_QUERY_PREFER_DETAILED_CHART_V1")
  set(TARGET_OLD [===[
  const wxPoint query_pixel = viewport.GetPixFromLL(query->lat, query->lon);
  ChartBase *target_chart = nullptr;
  if (canvas->m_singleChart &&
      canvas->m_singleChart->GetChartFamily() == CHART_FAMILY_VECTOR) {
    target_chart = canvas->m_singleChart;
  } else if (viewport.b_quilt && canvas->m_pQuilt) {
    target_chart = canvas->m_pQuilt->GetChartAtPix(viewport, query_pixel);
  }
  if (!target_chart) return false;
]===])
  set(TARGET_NEW [===[
  const wxPoint query_pixel = viewport.GetPixFromLL(query->lat, query->lon);
  ChartBase *target_chart = nullptr;

  // VECTOR_QUERY_PREFER_DETAILED_CHART_V1
  // Hover queries must stay cheap: inspect the position-specific chart stack,
  // but only use a detailed chart when it is already cached.  This recovers
  // objects from a detailed ENC immediately after zooming out without causing
  // chart loads on every mouse move.
  const bool prefer_detailed_chart =
      query->struct_size >= sizeof(PI_VectorQueryV1) &&
      (query->flags & PI_VECTOR_QUERY_PREFER_DETAILED_CHART_V1) != 0;
  if (prefer_detailed_chart && ChartData && ChartData->IsValid()) {
    ChartStack stack;
    ChartData->BuildChartStack(&stack, static_cast<float>(query->lat),
                               static_cast<float>(query->lon),
                               canvas->m_groupIndex);
    for (int i = 0; i < stack.nEntry; ++i) {
      const int db_index = stack.GetDBIndex(i);
      if (db_index < 0) continue;
      if (ChartData->GetDBChartFamily(db_index) != CHART_FAMILY_VECTOR)
        continue;
      if (!ChartData->IsChartInCache(db_index)) continue;
      ChartBase *candidate = ChartData->OpenChartFromDB(db_index, FULL_INIT);
      if (candidate && candidate->GetChartFamily() == CHART_FAMILY_VECTOR) {
        target_chart = candidate;
        break;
      }
    }
  }

  if (!target_chart) {
    if (canvas->m_singleChart &&
        canvas->m_singleChart->GetChartFamily() == CHART_FAMILY_VECTOR) {
      target_chart = canvas->m_singleChart;
    } else if (viewport.b_quilt && canvas->m_pQuilt) {
      target_chart = canvas->m_pQuilt->GetChartAtPix(viewport, query_pixel);
    }
  }
  if (!target_chart) return false;
]===])

  string(FIND "${C}" "${TARGET_OLD}" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate QueryVectorChartObjectsV1 target-chart selection block")
  endif()
  string(REPLACE "${TARGET_OLD}" "${TARGET_NEW}" C "${C}")
  file(WRITE "${OPENCPN_CPP}" "${C}")
  message(STATUS "Installed cached detailed-chart selection in OpenCPN vector query host")
else()
  message(STATUS "OpenCPN detailed-chart vector query selection already installed")
endif()

# -----------------------------------------------------------------------------
# Chart Inspector: use a two-pass hover policy.
#
# Pass 1 keeps the old, intuitive behavior: normal rendered objects from the
# active chart may be highlighted.
# Pass 2 runs only when pass 1 found nothing. It may inspect non-rendered
# objects in the most detailed cached chart, but accepts only navigation-relevant
# feature classes. This prevents arbitrary invisible depth/area/line geometry
# from glowing when the chart itself shows nothing there.
# -----------------------------------------------------------------------------
file(READ "${INSPECTOR_CPP}" P)
if(NOT P MATCHES "CHARTINSPECTOR_DETAILED_HIDDEN_FALLBACK_V1")
  if(NOT P MATCHES "CHARTINSPECTOR_VECTOR_HOVER_V1")
    message(FATAL_ERROR "Chart Inspector vector hover v1 must be installed first")
  endif()
  if(NOT P MATCHES "CI_INCLUDE_NON_RENDERED")
    message(FATAL_ERROR "Chart Inspector INCLUDE_NON_RENDERED support must be installed first")
  endif()
  if(NOT P MATCHES "CHARTINSPECTOR_HOVER_NEAREST_V1")
    message(FATAL_ERROR "Nearest-geometry hover ranking v1 must be installed first")
  endif()

  set(CONST_OLD [===[
constexpr uint32_t CI_SKIP_ATTRIBUTES = 1u;
constexpr uint32_t CI_INCLUDE_NON_RENDERED = 1u << 1;
constexpr uint32_t CI_GEOMETRY_ALL = 7u;
]===])
  set(CONST_NEW [===[
constexpr uint32_t CI_SKIP_ATTRIBUTES = 1u;
constexpr uint32_t CI_INCLUDE_NON_RENDERED = 1u << 1;
constexpr uint32_t CI_PREFER_DETAILED_CHART = 1u << 2;
constexpr uint32_t CI_GEOMETRY_ALL = 7u;
]===])
  string(FIND "${P}" "${CONST_OLD}" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate Chart Inspector hover constants")
  endif()
  string(REPLACE "${CONST_OLD}" "${CONST_NEW}" P "${P}")

  set(COLLECT_ANCHOR [===[
bool CI_CollectHover(const CI_VectorObjectV1 *o, void *user) {
]===])
  set(COLLECT_PREFIX [===[
// CHARTINSPECTOR_DETAILED_HIDDEN_FALLBACK_V1
static bool CI_IsHiddenNavigationFeature(const wxString &feature) {
  return feature.StartsWith("BOY") || feature.StartsWith("BCN") ||
         feature == "LIGHTS" || feature == "TOPMAR" ||
         feature == "DAYMAR" || feature == "LNDMRK" ||
         feature == "WRECKS" || feature == "UWTROC" ||
         feature == "OBSTRN" || feature == "MORFAC" ||
         feature == "OFSPLF" || feature == "PILPNT";
}

bool CI_CollectHover(const CI_VectorObjectV1 *o, void *user) {
]===])
  string(FIND "${P}" "${COLLECT_ANCHOR}" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate CI_CollectHover")
  endif()
  string(REPLACE "${COLLECT_ANCHOR}" "${COLLECT_PREFIX}" P "${P}")

  set(AFTER_COLLECT [===[
  *best = next;
  return true;
}
]===])
  set(AFTER_COLLECT_NEW [===[
  *best = next;
  return true;
}

static bool CI_CollectHiddenNavigationHover(const CI_VectorObjectV1 *o,
                                            void *user) {
  if (!o) return true;
  const wxString feature =
      wxString::FromUTF8(o->feature_class_utf8 ? o->feature_class_utf8 : "")
          .Upper();
  if (!CI_IsHiddenNavigationFeature(feature)) return true;
  return CI_CollectHover(o, user);
}
]===])
  string(FIND "${P}" "${AFTER_COLLECT}" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate end of CI_CollectHover")
  endif()
  string(REPLACE "${AFTER_COLLECT}" "${AFTER_COLLECT_NEW}" P "${P}")

  set(QUERY_FLAGS_OLD [===[
  q.flags = CI_SKIP_ATTRIBUTES | CI_INCLUDE_NON_RENDERED; q.geometry_mask = CI_GEOMETRY_ALL;
]===])
  set(QUERY_FLAGS_NEW [===[
  q.flags = CI_SKIP_ATTRIBUTES; q.geometry_mask = CI_GEOMETRY_ALL;
]===])
  string(FIND "${P}" "${QUERY_FLAGS_OLD}" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate current Chart Inspector hover query flags")
  endif()
  string(REPLACE "${QUERY_FLAGS_OLD}" "${QUERY_FLAGS_NEW}" P "${P}")

  set(BEST_OLD [===[
  CI_HoverCandidate best;
  best.cursorLat = m_cursorLat;
  best.cursorLon = m_cursorLon;
  queryFn(0, &q, CI_CollectHover, &best);
  m_lastHoverQueryMs = now; m_lastHoverQueryPosition = m_mousePosition;
]===])
  set(BEST_NEW [===[
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
  string(FIND "${P}" "${BEST_OLD}" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate current hover candidate query block")
  endif()
  string(REPLACE "${BEST_OLD}" "${BEST_NEW}" P "${P}")

  file(WRITE "${INSPECTOR_CPP}" "${P}")
  message(STATUS "Installed Chart Inspector two-pass detailed hidden hover fallback")
else()
  message(STATUS "Chart Inspector detailed hidden hover fallback already installed")
endif()

message(STATUS "Detailed-chart hidden hover fallback v1 complete")
message(STATUS "  visible hover remains active-chart/rendered-only")
message(STATUS "  hidden fallback uses largest-scale cached vector chart at cursor")
message(STATUS "  hidden fallback accepts navigation-relevant feature classes only")
