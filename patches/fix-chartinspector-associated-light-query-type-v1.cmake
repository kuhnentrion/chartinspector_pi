set(CPP "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()

file(READ "${CPP}" C)

if(C MATCHES "CHARTINSPECTOR_ASSOC_LIGHT_QUERY_TYPE_FIX_V1")
  message(STATUS "Chart Inspector associated-light query type fix v1 already installed")
  return()
endif()
if(NOT C MATCHES "CHARTINSPECTOR_ASSOCIATED_LIGHT_COLOURS_V1")
  message(FATAL_ERROR "Associated light/colours v1 must be installed first")
endif()

set(OLD "          PI_VectorQueryV1 lightQuery = q;\n")
set(NEW "          // CHARTINSPECTOR_ASSOC_LIGHT_QUERY_TYPE_FIX_V1\n          auto lightQuery = q;\n")

string(FIND "${C}" "${OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate associated LIGHTS query declaration")
endif()
string(REPLACE "${OLD}" "${NEW}" C "${C}")

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed Chart Inspector associated-light query type fix v1")
message(STATUS "  LIGHTS lookup now copies the already-correct local query ABI type")
message(STATUS "  no dependency on PI_VectorQueryV1 declaration in plugin headers")
