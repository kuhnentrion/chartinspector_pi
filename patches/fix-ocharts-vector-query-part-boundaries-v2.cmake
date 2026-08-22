if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required, e.g. -DOCHARTS_ROOT=C:/Users/Johannes/source/o-charts_pi")
endif()

file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()

file(READ "${CPP}" C)

if(C MATCHES "VECTOR_QUERY_PRESERVE_PART_ENDPOINTS_V2")
  message(STATUS "o-charts vector-query part endpoint fix v2 already installed")
  return()
endif()

if(NOT C MATCHES "VECTOR_QUERY_NATIVE_S57_V3")
  message(FATAL_ERROR "Native S57 vector query provider v3 must be installed first")
endif()

# Current eSENCChart.cpp contains two append_sm helpers with slightly different
# formatting. Both deduplicate against points.back() globally. At an S-57 part
# boundary this removes the shared start node of the next edge. A simple edge
# can then contain only one newly appended point and is dropped by the
# part.point_count >= 2 check. Preserve the shared endpoint instead.

set(OLD_ACTIVE [===[
    if (!points.empty()) {
      const auto &last = points.back();
      if (std::fabs(last.lat - lat) < 1e-10 &&
          std::fabs(last.lon - lon) < 1e-10)
        return;
    }
    points.push_back({lat, lon});
]===])

set(NEW_ACTIVE [===[
    // VECTOR_QUERY_PRESERVE_PART_ENDPOINTS_V2
    // Adjacent S-57 parts intentionally share an endpoint. Do not remove it
    // globally, otherwise a two-node edge can collapse to a one-point part.
    points.push_back({lat, lon});
]===])

set(OLD_SECONDARY [===[
        if (!points.empty()) {
          const auto &last = points.back();
          if (std::fabs(last.lat - lat) < 1e-10 &&
              std::fabs(last.lon - lon) < 1e-10) return;
        }
        points.push_back({lat, lon});
]===])

set(NEW_SECONDARY [===[
        // VECTOR_QUERY_PRESERVE_PART_ENDPOINTS_V2
        // Preserve the shared endpoint between adjacent S-57 edge parts.
        points.push_back({lat, lon});
]===])

string(FIND "${C}" "${OLD_ACTIVE}" ACTIVE_POS)
if(ACTIVE_POS EQUAL -1)
  message(FATAL_ERROR "Could not locate active append_sm duplicate suppression")
endif()
string(REPLACE "${OLD_ACTIVE}" "${NEW_ACTIVE}" C "${C}")

string(FIND "${C}" "${OLD_SECONDARY}" SECONDARY_POS)
if(SECONDARY_POS EQUAL -1)
  message(FATAL_ERROR "Could not locate secondary append_sm duplicate suppression")
endif()
string(REPLACE "${OLD_SECONDARY}" "${NEW_SECONDARY}" C "${C}")

string(REGEX MATCHALL "VECTOR_QUERY_PRESERVE_PART_ENDPOINTS_V2" MARKERS "${C}")
list(LENGTH MARKERS MARKER_COUNT)
if(NOT MARKER_COUNT EQUAL 2)
  message(FATAL_ERROR "Expected 2 part-endpoint replacements, found ${MARKER_COUNT}")
endif()

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed o-charts vector-query part endpoint fix v2")
message(STATUS "  active append_sm now preserves shared edge endpoints")
message(STATUS "  secondary append_sm now preserves shared edge endpoints")
message(STATUS "  two-node S-57 edges remain valid two-point parts")
message(STATUS "  expected result: complete polygon/line boundary highlighting")
