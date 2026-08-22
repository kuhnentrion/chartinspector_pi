if(NOT DEFINED OCHARTS_ROOT)
  message(FATAL_ERROR "OCHARTS_ROOT is required, e.g. -DOCHARTS_ROOT=C:/Users/Johannes/source/o-charts_pi")
endif()

file(TO_CMAKE_PATH "${OCHARTS_ROOT}" OCHARTS_ROOT)
set(CPP "${OCHARTS_ROOT}/src/eSENCChart.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()

file(READ "${CPP}" C)

if(C MATCHES "VECTOR_QUERY_PRESERVE_PART_ENDPOINTS_V1")
  message(STATUS "o-charts vector-query part endpoint fix v1 already installed")
  return()
endif()

if(NOT C MATCHES "VECTOR_QUERY_NATIVE_S57_V3")
  message(FATAL_ERROR "Native S57 vector query provider v3 must be installed first")
endif()
if(NOT C MATCHES "VECTOR_QUERY_STRICT_POINT_BUDGET_V1")
  message(FATAL_ERROR "Strict point-budget patch must be installed first")
endif()

# QueryVectorObjectsV1 emits line/area topology as multiple PI_VectorPartV1
# records, normally one part per S-57 edge. The old append_sm helper suppressed
# a point whenever it matched points.back() globally. This is wrong at a part
# boundary: the first node of edge N+1 normally equals the last node of edge N.
# Suppressing it can leave a simple two-node edge with only one newly appended
# point; that part is then discarded by the `point_count >= 2` guard. The result
# is exactly the observed alternating/missing polygon sides.
#
# Keep shared endpoints in the transport geometry. Consecutive duplicate
# vertices inside a part are harmless for drawing and preferable to deleting a
# complete topological edge. The point budget remains enforced by append_sm.
set(OLD [===[
    if (!points.empty()) {
      const auto &last = points.back();
      if (std::fabs(last.lat - lat) < 1e-10 &&
          std::fabs(last.lon - lon) < 1e-10)
        return;
    }
    points.push_back({lat, lon});
]===])

set(NEW [===[
    // VECTOR_QUERY_PRESERVE_PART_ENDPOINTS_V1
    // Do not deduplicate against the previous global point here. Adjacent
    // PI_VectorPartV1 records intentionally share their boundary endpoint.
    // Removing that point can collapse a two-node edge to one point and cause
    // the whole edge to be dropped.
    points.push_back({lat, lon});
]===])

string(REGEX MATCHALL "if \(!points.empty\(\)\) \{[\r\n ]+const auto &last = points.back\(\);[\r\n ]+if \(std::fabs\(last.lat - lat\) < 1e-10 &&[\r\n ]+std::fabs\(last.lon - lon\) < 1e-10\)[\r\n ]+return;[\r\n ]+\}[\r\n ]+points.push_back\(\{lat, lon\}\);" MATCHES "${C}")
list(LENGTH MATCHES BEFORE_COUNT)
if(BEFORE_COUNT LESS 1)
  message(FATAL_ERROR "Could not locate global append_sm duplicate suppression")
endif()

string(REPLACE "${OLD}" "${NEW}" C "${C}")

string(REGEX MATCHALL "VECTOR_QUERY_PRESERVE_PART_ENDPOINTS_V1" MARKERS "${C}")
list(LENGTH MARKERS MARKER_COUNT)
if(MARKER_COUNT LESS 1)
  message(FATAL_ERROR "Part endpoint replacement did not apply")
endif()

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed o-charts vector-query part endpoint fix v1")
message(STATUS "  shared endpoints between adjacent S-57 edges are preserved")
message(STATUS "  two-node edges can no longer collapse to one-point parts")
message(STATUS "  existing query point budgets remain enforced")
message(STATUS "  expected result: complete line and area boundary highlighting")
