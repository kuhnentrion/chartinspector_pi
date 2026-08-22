set(CPP "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()

file(READ "${CPP}" C)

if(C MATCHES "CHARTINSPECTOR_HIDDEN_LANDMARK_FILTER_V1")
  message(STATUS "Hidden landmark fallback filter v1 already installed")
  return()
endif()

if(NOT C MATCHES "CHARTINSPECTOR_DETAILED_HIDDEN_FALLBACK_V1")
  message(FATAL_ERROR "Detailed hidden hover fallback v1 must be installed first")
endif()

set(OLD [===[
// CHARTINSPECTOR_DETAILED_HIDDEN_FALLBACK_V1
static bool CI_IsHiddenNavigationFeature(const wxString &feature) {
  return feature.StartsWith("BOY") || feature.StartsWith("BCN") ||
         feature == "LIGHTS" || feature == "TOPMAR" ||
         feature == "DAYMAR" || feature == "LNDMRK" ||
         feature == "WRECKS" || feature == "UWTROC" ||
         feature == "OBSTRN" || feature == "MORFAC" ||
         feature == "OFSPLF" || feature == "PILPNT";
}
]===])

set(NEW [===[
// CHARTINSPECTOR_DETAILED_HIDDEN_FALLBACK_V1
// CHARTINSPECTOR_HIDDEN_LANDMARK_FILTER_V1
static bool CI_IsHiddenNavigationFeature(const wxString &feature) {
  // Hidden fallback is intentionally limited to navigation objects where
  // defeating SCAMIN is useful. Generic land landmarks (LNDMRK), such as
  // churches and wind turbines, remain hoverable when actually rendered but
  // are not resurrected when the chart portrayal hides them by scale.
  return feature.StartsWith("BOY") || feature.StartsWith("BCN") ||
         feature == "LIGHTS" || feature == "TOPMAR" ||
         feature == "DAYMAR" || feature == "WRECKS" ||
         feature == "UWTROC" || feature == "OBSTRN" ||
         feature == "MORFAC" || feature == "OFSPLF" ||
         feature == "PILPNT";
}
]===])

string(FIND "${C}" "${OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate hidden navigation feature filter")
endif()

string(REPLACE "${OLD}" "${NEW}" C "${C}")
file(WRITE "${CPP}" "${C}")

message(STATUS "Installed Chart Inspector hidden landmark filter v1")
message(STATUS "  LNDMRK no longer participates in SCAMIN-bypassing hidden fallback")
message(STATUS "  visible churches, wind turbines and other landmarks remain hoverable")
message(STATUS "  hidden buoys/beacons/lights and other navigation hazards remain eligible")
