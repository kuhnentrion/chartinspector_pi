set(HDR "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.h")
set(CPP "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.cpp")
foreach(P "${HDR}" "${CPP}")
  if(NOT EXISTS "${P}")
    message(FATAL_ERROR "Missing ${P}")
  endif()
endforeach()

file(READ "${HDR}" H)
file(READ "${CPP}" C)

if(C MATCHES "CHARTINSPECTOR_FULL_HIGHLIGHT_GEOMETRY_V1")
  message(STATUS "Chart Inspector full highlight geometry v1 already installed")
  return()
endif()

if(NOT C MATCHES "CHARTINSPECTOR_SELECTABLE_POLICY_V2")
  message(FATAL_ERROR "Selectable-object policy v2 must be installed first")
endif()
# CHARTINSPECTOR_HOVER_INFO_V1 is declared on the hover-info member block in
# chartinspector_pi.h, not in the implementation file.
if(NOT H MATCHES "CHARTINSPECTOR_HOVER_INFO_V1")
  message(FATAL_ERROR "Live hover info v1 must be installed first")
endif()

# The original hover query deliberately capped each object at 50 points. That
# keeps cursor probing cheap, but it also means long lines and area boundaries
# are visibly truncated when drawn as the cyan highlight. Raise the probe budget
# modestly for better distance ranking, then fetch a much larger geometry only
# when the selected object changes.
set(BUDGET_OLD [===[
  q.max_objects = 8; q.max_points_per_object = 50;
]===])
set(BUDGET_NEW [===[
  // CHARTINSPECTOR_FULL_HIGHLIGHT_GEOMETRY_V1
  q.max_objects = 8; q.max_points_per_object = 512;
]===])
string(FIND "${C}" "${BUDGET_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate hover probe point budget")
endif()
string(REPLACE "${BUDGET_OLD}" "${BUDGET_NEW}" C "${C}")

# If the cursor is still on the already-detailed object, preserve the cached
# full geometry instead of overwriting it with the shorter probe geometry on
# every mouse move.
set(KEY_OLD [===[
    if (key != m_hoverInfoKey) {
      CI_HoverCandidate details;
]===])
set(KEY_NEW [===[
    if (key == m_hoverInfoKey && m_hasHoverGeometry &&
        m_hoverFeature == best.feature) {
      m_lastHoverQueryMs = now;
      m_lastHoverQueryPosition = m_mousePosition;
      return;
    }

    if (key != m_hoverInfoKey) {
      CI_HoverCandidate details;
]===])
string(FIND "${C}" "${KEY_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate hover detail key block")
endif()
string(REPLACE "${KEY_OLD}" "${KEY_NEW}" C "${C}")

# Re-query the selected object with a large geometry budget. This runs only on
# object change, so the normal 75 ms hover probing remains lightweight. The
# returned detailed candidate replaces the probe candidate before the existing
# member-copy code stores the geometry for rendering.
set(DETAIL_OLD [===[
      details.includeFilter = m_featureFilter;
      q.flags &= ~CI_SKIP_ATTRIBUTES;
      queryFn(0, &q, CI_CollectHover, &details);
      if (!details.points.empty()) {
        UpdateHoverInfoPanel(details.feature, details.objectName,
                             details.attributes,
                             static_cast<int>(details.geometry));
        m_hoverInfoKey = key;
]===])
set(DETAIL_NEW [===[
      details.includeFilter = m_featureFilter;
      q.flags &= ~CI_SKIP_ATTRIBUTES;
      q.max_points_per_object = 16384;
      queryFn(0, &q, CI_CollectHover, &details);
      if (!details.points.empty()) {
        best = details;
        UpdateHoverInfoPanel(details.feature, details.objectName,
                             details.attributes,
                             static_cast<int>(details.geometry));
        m_hoverInfoKey = key;
]===])
string(FIND "${C}" "${DETAIL_OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate hover detail re-query block")
endif()
string(REPLACE "${DETAIL_OLD}" "${DETAIL_NEW}" C "${C}")

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed Chart Inspector full highlight geometry v1")
message(STATUS "  hover probe budget raised from 50 to 512 points")
message(STATUS "  selected object is re-queried once with up to 16384 points")
message(STATUS "  full geometry is cached while cursor remains on the same object")
message(STATUS "  long lines and complete area outlines can now be highlighted")
