if(NOT DEFINED OPENCPN_ROOT)
  message(FATAL_ERROR "OPENCPN_ROOT is required, e.g. -DOPENCPN_ROOT=C:/Users/Johannes/source/OpenCPN")
endif()
if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required, e.g. -DOCHARTS_ROOT=C:/Users/Johannes/source/o-charts_pi")
endif()

file(TO_CMAKE_PATH "${OPENCPN_ROOT}" OPENCPN_ROOT)
file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)

set(OPENCPN_API "${OPENCPN_ROOT}/include/ocpn_plugin.h")
set(OCHARTS_API16 "${OCHARTS_ROOT}/api-16/ocpn_plugin.h")
set(OCHARTS_API17 "${OCHARTS_ROOT}/opencpn-libs/api-17/ocpn_plugin.h")
set(OCHARTS_CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
set(INSPECTOR_CPP "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.cpp")

foreach(P "${OPENCPN_API}" "${OCHARTS_API16}" "${OCHARTS_API17}" "${OCHARTS_CPP}" "${INSPECTOR_CPP}")
  if(NOT EXISTS "${P}")
    message(FATAL_ERROR "Required file not found: ${P}")
  endif()
endforeach()

# -----------------------------------------------------------------------------
# Public/bundled API: append a second flags bit without changing the struct ABI.
# -----------------------------------------------------------------------------
function(add_non_rendered_flag PATH)
  file(READ "${PATH}" H)
  if(H MATCHES "PI_VECTOR_QUERY_INCLUDE_NON_RENDERED_V1")
    message(STATUS "Non-rendered query flag already present in ${PATH}")
    return()
  endif()

  set(OLD [===[
enum PI_VectorQueryFlagsV1 : uint32_t {
  PI_VECTOR_QUERY_SKIP_ATTRIBUTES_V1 = 1u << 0
};
]===])
  set(NEW [===[
enum PI_VectorQueryFlagsV1 : uint32_t {
  PI_VECTOR_QUERY_SKIP_ATTRIBUTES_V1       = 1u << 0,
  PI_VECTOR_QUERY_INCLUDE_NON_RENDERED_V1 = 1u << 1
};
]===])

  string(FIND "${H}" "${OLD}" POS)
  if(POS EQUAL -1)
    message(FATAL_ERROR "Could not locate PI_VectorQueryFlagsV1 in ${PATH}")
  endif()
  string(REPLACE "${OLD}" "${NEW}" H "${H}")
  file(WRITE "${PATH}" "${H}")
  message(STATUS "Added PI_VECTOR_QUERY_INCLUDE_NON_RENDERED_V1 to ${PATH}")
endfunction()

add_non_rendered_flag("${OPENCPN_API}")
add_non_rendered_flag("${OCHARTS_API16}")
add_non_rendered_flag("${OCHARTS_API17}")

# -----------------------------------------------------------------------------
# o-charts provider: when requested, bypass S-52 ObjectRenderCheck while keeping
# the existing geometric hit test. This includes objects hidden by current
# presentation rules (for example SCAMIN/display category) if they are present
# in the provider's razRules.
#
# eSENCChart.cpp currently contains two QueryVectorObjectsV1 implementations in
# separate compilation regions. The insertion below matches query_flags in both
# provider bodies. The render-check replacements additionally include
# query->lat in their anchors, so they cannot touch the older
# GetObjRuleListAtLatLon selection code elsewhere in this file.
# -----------------------------------------------------------------------------
file(READ "${OCHARTS_CPP}" C)

if(NOT C MATCHES "VECTOR_QUERY_INCLUDE_NON_RENDERED_V1")
  set(FLAGS [===[
  const uint32_t query_flags = has_flags ? query->flags : 0u;
]===])
  set(FLAGS_NEW [===[
  const uint32_t query_flags = has_flags ? query->flags : 0u;

  // VECTOR_QUERY_INCLUDE_NON_RENDERED_V1
  const bool include_non_rendered =
      (query_flags & PI_VECTOR_QUERY_INCLUDE_NON_RENDERED_V1) != 0;
  auto rule_is_queryable = [&](ObjRazRules *rule) {
    if (!rule || !rule->obj) return false;
    return include_non_rendered || ps52plib->ObjectRenderCheck(rule);
  };
]===])

  string(FIND "${C}" "${FLAGS}" FLAGS_POS)
  if(FLAGS_POS EQUAL -1)
    message(FATAL_ERROR "Could not locate query_flags in ${OCHARTS_CPP}")
  endif()
  string(REPLACE "${FLAGS}" "${FLAGS_NEW}" C "${C}")

  set(TOP_RENDER [===[
ps52plib->ObjectRenderCheck(top) &&
          DoesLatLonSelectObject(static_cast<float>(query->lat),
]===])
  set(TOP_QUERY [===[
rule_is_queryable(top) &&
          DoesLatLonSelectObject(static_cast<float>(query->lat),
]===])
  set(CHILD_RENDER [===[
ps52plib->ObjectRenderCheck(child) &&
            DoesLatLonSelectObject(static_cast<float>(query->lat),
]===])
  set(CHILD_QUERY [===[
rule_is_queryable(child) &&
            DoesLatLonSelectObject(static_cast<float>(query->lat),
]===])

  string(FIND "${C}" "${TOP_RENDER}" TOP_POS)
  if(TOP_POS EQUAL -1)
    message(FATAL_ERROR "Could not locate provider top-level ObjectRenderCheck")
  endif()
  string(REPLACE "${TOP_RENDER}" "${TOP_QUERY}" C "${C}")

  string(FIND "${C}" "${CHILD_RENDER}" CHILD_POS)
  if(CHILD_POS EQUAL -1)
    message(FATAL_ERROR "Could not locate provider child ObjectRenderCheck")
  endif()
  string(REPLACE "${CHILD_RENDER}" "${CHILD_QUERY}" C "${C}")

  # Guard against an incomplete provider conversion. Any remaining render check
  # immediately followed by query->lat would still suppress non-rendered
  # candidates in QueryVectorObjectsV1.
  string(FIND "${C}" "ObjectRenderCheck(top) &&\n          DoesLatLonSelectObject(static_cast<float>(query->lat)" LEFT_TOP)
  string(FIND "${C}" "ObjectRenderCheck(child) &&\n            DoesLatLonSelectObject(static_cast<float>(query->lat)" LEFT_CHILD)
  if(NOT LEFT_TOP EQUAL -1 OR NOT LEFT_CHILD EQUAL -1)
    message(FATAL_ERROR "Not all QueryVectorObjectsV1 render checks were converted")
  endif()

  file(WRITE "${OCHARTS_CPP}" "${C}")
  message(STATUS "Enabled INCLUDE_NON_RENDERED selection in both o-charts provider paths")
else()
  message(STATUS "o-charts INCLUDE_NON_RENDERED provider support already installed")
endif()

# -----------------------------------------------------------------------------
# Chart Inspector hover/highlight query: request non-rendered candidates while
# still skipping attributes for the fast geometry-only hover path.
# -----------------------------------------------------------------------------
file(READ "${INSPECTOR_CPP}" P)

if(P MATCHES "CHARTINSPECTOR_VECTOR_HOVER_V1")
  if(NOT P MATCHES "CI_INCLUDE_NON_RENDERED")
    set(CI_FLAGS_OLD [===[
constexpr uint32_t CI_SKIP_ATTRIBUTES = 1u;
constexpr uint32_t CI_GEOMETRY_ALL = 7u;
]===])
    set(CI_FLAGS_NEW [===[
constexpr uint32_t CI_SKIP_ATTRIBUTES = 1u;
constexpr uint32_t CI_INCLUDE_NON_RENDERED = 1u << 1;
constexpr uint32_t CI_GEOMETRY_ALL = 7u;
]===])
    string(FIND "${P}" "${CI_FLAGS_OLD}" CI_FLAGS_POS)
    if(CI_FLAGS_POS EQUAL -1)
      message(FATAL_ERROR "Could not locate Chart Inspector hover flag constants")
    endif()
    string(REPLACE "${CI_FLAGS_OLD}" "${CI_FLAGS_NEW}" P "${P}")

    set(CI_QUERY_OLD "q.flags = CI_SKIP_ATTRIBUTES; q.geometry_mask = CI_GEOMETRY_ALL;")
    set(CI_QUERY_NEW "q.flags = CI_SKIP_ATTRIBUTES | CI_INCLUDE_NON_RENDERED; q.geometry_mask = CI_GEOMETRY_ALL;")
    string(FIND "${P}" "${CI_QUERY_OLD}" CI_QUERY_POS)
    if(CI_QUERY_POS EQUAL -1)
      message(FATAL_ERROR "Could not locate Chart Inspector hover query flags")
    endif()
    string(REPLACE "${CI_QUERY_OLD}" "${CI_QUERY_NEW}" P "${P}")

    file(WRITE "${INSPECTOR_CPP}" "${P}")
    message(STATUS "Chart Inspector hover query now includes non-rendered objects")
  else()
    message(STATUS "Chart Inspector non-rendered hover query already installed")
  endif()
else()
  message(WARNING "CHARTINSPECTOR_VECTOR_HOVER_V1 is not applied to src/chartinspector_pi.cpp; provider/API support was installed, but the hover caller was left unchanged")
endif()

message(STATUS "Vector query non-rendered upgrade v1 complete")
message(STATUS "  API flag bit: 1 << 1")
message(STATUS "  default behavior unchanged unless the caller sets the flag")
message(STATUS "  o-charts still requires DoesLatLonSelectObject for geometric selection")
