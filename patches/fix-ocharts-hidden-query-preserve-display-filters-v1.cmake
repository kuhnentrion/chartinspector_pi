if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required, e.g. -DOCHARTS_ROOT=C:/Users/Johannes/source/o-charts_pi")
endif()

file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(OCHARTS_CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
if(NOT EXISTS "${OCHARTS_CPP}")
  message(FATAL_ERROR "Missing ${OCHARTS_CPP}")
endif()

file(READ "${OCHARTS_CPP}" C)

if(C MATCHES "VECTOR_QUERY_PRESERVE_DISPLAY_FILTERS_V1")
  message(STATUS "o-charts hidden-query display-filter preservation v1 already installed")
  return()
endif()

if(NOT C MATCHES "VECTOR_QUERY_INCLUDE_NON_RENDERED_V1")
  message(FATAL_ERROR "INCLUDE_NON_RENDERED provider support must be installed first")
endif()

# The first INCLUDE_NON_RENDERED implementation bypassed ObjectRenderCheck()
# completely. That also bypassed intentional S-52 visibility choices such as
# the Anchor Info switch, which puts CBLSUB/PIPARE/SBDARE/etc. on the NoShow
# list. The hover feature only needs to defeat scale suppression (SCAMIN and
# SUPER_SCAMIN), not user-selected display filters.
#
# ObjectRenderCheckRules(rule, true) is the normal S-52 visibility path which
# honors:
#   * current display category / Mariner's Standard visibility
#   * explicit NoShow entries (e.g. Anchor Info off)
#   * sounding/meta visibility
#   * conditional-symbology category changes
#   * object validity dates
#
# Temporarily disabling only the two scale filters around that call gives the
# intended semantics while leaving the normal/default query path untouched.
set(OLD [===[
  auto rule_is_queryable = [&](ObjRazRules *rule) {
    if (!rule || !rule->obj) return false;
    return include_non_rendered || ps52plib->ObjectRenderCheck(rule);
  };
]===])

set(NEW [===[
  auto rule_is_queryable = [&](ObjRazRules *rule) {
    if (!rule || !rule->obj) return false;
    if (!include_non_rendered) return ps52plib->ObjectRenderCheck(rule);

    // VECTOR_QUERY_PRESERVE_DISPLAY_FILTERS_V1
    // Keep all current S-52/user visibility rules, but ignore scale-only
    // suppression so a detailed navigation object may still be queried after
    // it has disappeared because of SCAMIN.
    const bool use_scamin = ps52plib->m_bUseSCAMIN;
    const bool use_super_scamin = ps52plib->m_bUseSUPER_SCAMIN;
    ps52plib->m_bUseSCAMIN = false;
    ps52plib->m_bUseSUPER_SCAMIN = false;
    const bool queryable = ps52plib->ObjectRenderCheckRules(rule, true);
    ps52plib->m_bUseSCAMIN = use_scamin;
    ps52plib->m_bUseSUPER_SCAMIN = use_super_scamin;
    return queryable;
  };
]===])

string(FIND "${C}" "${OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate INCLUDE_NON_RENDERED rule_is_queryable block")
endif()

# eSENCChart.cpp currently carries two active QueryVectorObjectsV1 provider
# bodies. string(REPLACE intentionally updates both identical lambdas.
string(REPLACE "${OLD}" "${NEW}" C "${C}")

# Verify both active provider copies received the new marker.
string(REGEX MATCHALL "VECTOR_QUERY_PRESERVE_DISPLAY_FILTERS_V1" MARKERS "${C}")
list(LENGTH MARKERS MARKER_COUNT)
if(NOT MARKER_COUNT EQUAL 2)
  message(FATAL_ERROR "Expected 2 provider replacements, found ${MARKER_COUNT}")
endif()

file(WRITE "${OCHARTS_CPP}" "${C}")
message(STATUS "Installed o-charts hidden-query display-filter preservation v1")
message(STATUS "  SCAMIN and SUPER_SCAMIN may be ignored for hover")
message(STATUS "  S-52 display category and NoShow switches remain authoritative")
message(STATUS "  Anchor Info off now suppresses CBLSUB/PIPARE/SBDARE hover targets")
message(STATUS "  normal vector-query behavior remains unchanged")
