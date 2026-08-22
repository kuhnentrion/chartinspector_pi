set(CPP "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()

file(READ "${CPP}" C)

if(C MATCHES "CHARTINSPECTOR_NAV_DEPTH_BUILD_FIX_V1")
  message(STATUS "Chart Inspector navigation depth build fix v1 already installed")
  return()
endif()

if(NOT C MATCHES "CHARTINSPECTOR_NAVIGATION_INFO_V1")
  message(FATAL_ERROR "Navigation info v1 must be installed first")
endif()

set(OLD [===[
static wxString CI_UserDepth(double metres) {
  const double value = toUsrDepth_Plugin(metres);
  return wxString::Format("%g ", value) + getUsrDepthUnit_Plugin();
}
]===])

set(NEW [===[
// CHARTINSPECTOR_NAV_DEPTH_BUILD_FIX_V1
static wxString CI_UserDepth(double metres) {
  // S-57 depth and clearance values are encoded in metres. Keep the display
  // independent of optional/newer OpenCPN conversion helpers so the plugin
  // remains buildable against the API headers used by current plugin builds.
  // A host-unit adapter can be added later without changing the navigation
  // prioritisation or S-57 decoding logic.
  return wxString::Format("%g m", metres);
}
]===])

string(FIND "${C}" "${OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate CI_UserDepth using OpenCPN conversion helpers")
endif()
string(REPLACE "${OLD}" "${NEW}" C "${C}")

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed Chart Inspector navigation depth build fix v1")
message(STATUS "  removed dependency on unavailable toUsrDepth_Plugin helpers")
message(STATUS "  S-57 depths and clearances are displayed correctly in metres")
message(STATUS "  navigation-first information layout remains unchanged")
