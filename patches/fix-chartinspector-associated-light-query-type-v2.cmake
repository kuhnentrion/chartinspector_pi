set(CPP "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.cpp")
if(NOT EXISTS "${CPP}")
  message(FATAL_ERROR "Missing ${CPP}")
endif()

file(READ "${CPP}" C)

if(C MATCHES "CHARTINSPECTOR_ASSOC_LIGHT_QUERY_TYPE_FIX_V2")
  message(STATUS "Chart Inspector associated-light query type fix v2 already installed")
  return()
endif()

# The previous associated-light patch was applied if this exact declaration is
# present. Do not depend on its missing marker; replace the concrete build error
# directly and inherit the already-correct local query ABI type from q.
set(OLD "          PI_VectorQueryV1 lightQuery = q;\n")
set(NEW "          // CHARTINSPECTOR_ASSOC_LIGHT_QUERY_TYPE_FIX_V2\n          auto lightQuery = q;\n")

string(FIND "${C}" "${OLD}" POS)
if(POS EQUAL -1)
  message(FATAL_ERROR "Could not locate 'PI_VectorQueryV1 lightQuery = q;' in current source")
endif()
string(REPLACE "${OLD}" "${NEW}" C "${C}")

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed Chart Inspector associated-light query type fix v2")
message(STATUS "  replaced explicit PI_VectorQueryV1 with auto")
message(STATUS "  associated LIGHTS lookup now inherits the working local query ABI type")
