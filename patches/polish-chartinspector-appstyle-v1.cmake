set(ROOT "${CMAKE_CURRENT_LIST_DIR}/..")
set(H "${ROOT}/src/ui/app_style.h")
set(S "${ROOT}/src/ui/app_style.cpp")
set(CPP "${ROOT}/src/chartinspector_pi.cpp")

foreach(P "${H}" "${S}" "${CPP}")
  if(NOT EXISTS "${P}")
    message(FATAL_ERROR "Missing ${P}; AppStyle v3 must be installed first")
  endif()
endforeach()

file(READ "${H}" AH)
file(READ "${S}" AS)
file(READ "${CPP}" C)

string(FIND "${C}" "CHARTINSPECTOR_APPSTYLE_POLISH_V1" ALREADY)
if(NOT ALREADY EQUAL -1)
  message(STATUS "Chart Inspector AppStyle polish v1 already installed")
  return()
endif()

# Card geometry: slightly softer and less boxy.
string(REPLACE "static const int kCardRadius = 8;"
               "static const int kCardRadius = 10;" AH "${AH}")
file(WRITE "${H}" "${AH}")

# Softer Day card, quieter border, and a genuinely secondary text tone.
set(PAL_OLD [===[
  const bool dark = scheme == PI_GLOBAL_COLOR_SCHEME_DUSK ||
                    scheme == PI_GLOBAL_COLOR_SCHEME_NIGHT;
  const wxColour white(255, 255, 255);
  p.cardBackground = Blend(p.windowBackground, white, dark ? 0.10 : 0.72);
  p.cardBorder = Blend(p.windowBackground, p.textPrimary, dark ? 0.26 : 0.18);

  p.accent = wxColour(0, 205, 225);
]===])
set(PAL_NEW [===[
  const bool dark = scheme == PI_GLOBAL_COLOR_SCHEME_DUSK ||
                    scheme == PI_GLOBAL_COLOR_SCHEME_NIGHT;
  const wxColour white(255, 255, 255);
  p.cardBackground = Blend(p.windowBackground, white, dark ? 0.08 : 0.48);
  p.cardBorder = Blend(p.windowBackground, p.textPrimary, dark ? 0.20 : 0.12);
  p.textSecondary = Blend(p.windowBackground, p.textPrimary, dark ? 0.70 : 0.55);

  p.accent = wxColour(0, 205, 225);
]===])
string(FIND "${AS}" "${PAL_OLD}" PPOS)
if(PPOS EQUAL -1)
  message(FATAL_ERROR "Could not locate AppStyle palette block")
endif()
string(REPLACE "${PAL_OLD}" "${PAL_NEW}" AS "${AS}")

# Labels should guide scanning without competing with the values/title.
set(LABEL_OLD [===[
wxFont AppStyle::LabelFont(const wxFont &base) {
  wxFont f = base;
  f.SetWeight(wxFONTWEIGHT_BOLD);
  return f;
}
]===])
set(LABEL_NEW [===[
wxFont AppStyle::LabelFont(const wxFont &base) {
  wxFont f = base;
  f.SetWeight(wxFONTWEIGHT_NORMAL);
  return f;
}
]===])
string(FIND "${AS}" "${LABEL_OLD}" LPOS)
if(LPOS EQUAL -1)
  message(FATAL_ERROR "Could not locate LabelFont")
endif()
string(REPLACE "${LABEL_OLD}" "${LABEL_NEW}" AS "${AS}")
file(WRITE "${S}" "${AS}")

# Parse numeric prefixes such as "2deg;", "5s" and "12 Nm" as well as plain
# S-57 numbers. This keeps the display robust if a provider returns a partly
# decoded value rather than the raw numeric token.
set(PARSE_OLD [===[
static bool CI_ParseNumber(wxString raw, double *value) {
  if (!value) return false;
  raw.Trim(true);
  raw.Trim(false);
  raw.Replace(",", ".");
  return raw.ToDouble(value);
}
]===])
set(PARSE_NEW [===[
// CHARTINSPECTOR_APPSTYLE_POLISH_V1
static bool CI_ParseNumber(wxString raw, double *value) {
  if (!value) return false;
  raw.Trim(true);
  raw.Trim(false);
  raw.Replace(",", ".");
  if (raw.ToDouble(value)) return true;

  wxString numeric;
  bool seenDigit = false;
  for (size_t i = 0; i < raw.length(); ++i) {
    const wxChar ch = raw[i];
    const bool digit = ch >= '0' && ch <= '9';
    const bool allowed = digit || ch == '+' || ch == '-' || ch == '.';
    if (!allowed) {
      if (seenDigit) break;
      continue;
    }
    numeric += ch;
    if (digit) seenDigit = true;
  }
  return seenDigit && numeric.ToDouble(value);
}
]===])
string(FIND "${C}" "${PARSE_OLD}" NPOS)
if(NPOS EQUAL -1)
  message(FATAL_ERROR "Could not locate CI_ParseNumber")
endif()
string(REPLACE "${PARSE_OLD}" "${PARSE_NEW}" C "${C}")

# Remove provider punctuation/code debris from readable values.
set(CLEAN_OLD [===[
  out.Trim(true);
  out.Trim(false);
  return out;
}
]===])
set(CLEAN_NEW [===[
  out.Trim(true);
  out.Trim(false);
  while (out.EndsWith(";")) {
    out.RemoveLast();
    out.Trim(true);
  }
  return out;
}
]===])
string(FIND "${C}" "${CLEAN_OLD}" CLEANPOS)
if(CLEANPOS EQUAL -1)
  message(FATAL_ERROR "Could not locate CI_CleanDecodedCodes tail")
endif()
string(REPLACE "${CLEAN_OLD}" "${CLEAN_NEW}" C "${C}")

# Proper degree glyphs for orientation and light sectors.
set(DEG_OLD [===[
      return label + ": " + wxString::Format("%g deg", degrees);
]===])
set(DEG_NEW [===[
      return label + ": " + wxString::Format("%g", degrees) +
             wxString::FromUTF8("°");
]===])
string(FIND "${C}" "${DEG_OLD}" DPOS)
if(DPOS EQUAL -1)
  message(FATAL_ERROR "Could not locate degree formatting")
endif()
string(REPLACE "${DEG_OLD}" "${DEG_NEW}" C "${C}")

# Give the technical footer more breathing room from the navigation card.
set(TECH_OLD [===[
    root->Add(m_hoverInfoBody, 0,
              wxEXPAND | wxLEFT | wxRIGHT | wxTOP | wxBOTTOM,
              ci_ui::AppStyle::kSpaceMd);
]===])
set(TECH_NEW [===[
    root->Add(m_hoverInfoBody, 0,
              wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM,
              ci_ui::AppStyle::kSpaceMd);
    root->SetItemMinSize(m_hoverInfoBody, -1, -1);
]===])
# Do not fail if wx layout differs; the existing spacing is already acceptable.
string(FIND "${C}" "${TECH_OLD}" TPOS)
if(NOT TPOS EQUAL -1)
  string(REPLACE "${TECH_OLD}" "${TECH_NEW}" C "${C}")
endif()

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed Chart Inspector AppStyle polish v1")
message(STATUS "  card radius increased to 10px and border contrast reduced")
message(STATUS "  labels are quieter so values/title carry the hierarchy")
message(STATUS "  technical text uses a more muted secondary tone")
message(STATUS "  provider values like 2deg;, 5s and 12 Nm are normalized")
message(STATUS "  bearings/sectors use the degree symbol")
