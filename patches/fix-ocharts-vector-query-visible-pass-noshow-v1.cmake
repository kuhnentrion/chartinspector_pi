if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required, e.g. -DOCHARTS_ROOT=C:/Users/Johannes/source/o-charts_pi")
endif()

file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(OCHARTS_CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
if(NOT EXISTS "${OCHARTS_CPP}")
  message(FATAL_ERROR "Missing ${OCHARTS_CPP}")
endif()

file(READ "${OCHARTS_CPP}" C)

if(C MATCHES "VECTOR_QUERY_VISIBLE_PASS_NOSHOW_V1")
  message(STATUS "o-charts visible vector-query NoShow fix v1 already installed")
  return()
endif()

if(NOT C MATCHES "VECTOR_QUERY_PRESERVE_DISPLAY_FILTERS_V1")
  message(FATAL_ERROR "Display-filter preservation v1 must be installed first")
endif()

# The visible/default branch still used ObjectRenderCheck(), which checks
# position/category/SCAMIN but does not consult the S-52 NoShow list. As a
# result CBLSUB/PIPARE/SBDARE could be returned in the normal hover pass even
# when OpenCPN's Anchor Info switch deliberately hid them.
#
# ObjectRenderCheckRules(rule, true) is the stronger visibility test used here:
# it honors NoShow, display category, conditional-category changes and dates,
# while retaining normal SCAMIN behavior because the scale flags remain enabled
# in the default branch.
set(OLD [===[
    if (!include_non_rendered) return ps52plib->ObjectRenderCheck(rule);

    // VECTOR_QUERY_PRESERVE_DISPLAY_FILTERS_V1
]===])

set(NEW [===[
    // VECTOR_QUERY_VISIBLE_PASS_NOSHOW_V1
    if (!include_non_rendered)
      return ps52plib->ObjectRenderCheckRules(rule, true);

    // VECTOR_QUERY_PRESERVE_DISPLAY_FILTERS_V1
]===])

string(FIND "${C}" "${OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate visible/default rule_is_queryable branch")
endif()

# eSENCChart.cpp has two active QueryVectorObjectsV1 provider bodies.
string(REPLACE "${OLD}" "${NEW}" C "${C}")

string(REGEX MATCHALL "VECTOR_QUERY_VISIBLE_PASS_NOSHOW_V1" MARKERS "${C}")
list(LENGTH MARKERS MARKER_COUNT)
if(NOT MARKER_COUNT EQUAL 2)
  message(FATAL_ERROR "Expected 2 visible-pass replacements, found ${MARKER_COUNT}")
endif()

file(WRITE "${OCHARTS_CPP}" "${C}")
message(STATUS "Installed o-charts visible vector-query NoShow fix v1")
message(STATUS "  normal hover now honors S-52 NoShow / Anchor Info")
message(STATUS "  normal hover still honors SCAMIN")
message(STATUS "  hidden fallback still ignores scale only, not display switches")
