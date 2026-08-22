set(HDR "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.h")
set(CPP "${CMAKE_CURRENT_LIST_DIR}/../src/chartinspector_pi.cpp")
foreach(P "${HDR}" "${CPP}")
  if(NOT EXISTS "${P}")
    message(FATAL_ERROR "Missing ${P}")
  endif()
endforeach()

file(READ "${HDR}" H)
file(READ "${CPP}" C)

if(C MATCHES "CHARTINSPECTOR_ASSOCIATED_LIGHT_COLOURS_V1")
  message(STATUS "Chart Inspector associated light/colours v1 already installed")
  return()
endif()
if(NOT C MATCHES "CHARTINSPECTOR_PROPERTY_GRID_V1")
  message(FATAL_ERROR "Property grid v1 must be installed first")
endif()
if(NOT C MATCHES "CHARTINSPECTOR_PROPERTY_GRID_COLOUR_ACCESS_FIX_V1")
  message(FATAL_ERROR "Property-grid colour access fix v1 must be installed first")
endif()

# -----------------------------------------------------------------------------
# Hover info method receives optional attributes from a co-located LIGHTS
# object. Keep them separate from the selected aid's attributes so COLOUR etc.
# cannot collide.
# -----------------------------------------------------------------------------
set(H_OLD [===[
  void UpdateHoverInfoPanel(const wxString &feature,
                            const wxString &objectName,
                            const wxString &attributes, int geometryType);
]===])
set(H_NEW [===[
  void UpdateHoverInfoPanel(const wxString &feature,
                            const wxString &objectName,
                            const wxString &attributes, int geometryType,
                            const wxString &associatedLightAttributes = wxEmptyString);
]===])
string(FIND "${H}" "${H_OLD}" HPOS)
if(HPOS EQUAL -1)
  message(FATAL_ERROR "Could not locate UpdateHoverInfoPanel declaration")
endif()
string(REPLACE "${H_OLD}" "${H_NEW}" H "${H}")
file(WRITE "${HDR}" "${H}")

# -----------------------------------------------------------------------------
# SignalColour previously understood numeric S-57 colour codes only. Vector
# providers can return already-decoded strings such as Green or Red(3), so also
# recognise names and trailing numeric decode codes.
# -----------------------------------------------------------------------------
set(SIG_START "wxColour ChartInspectorPi::SignalColour(const wxString &value) const {")
set(SIG_END "wxString ChartInspectorPi::BuildLightSummary")
string(FIND "${C}" "${SIG_START}" SSTART)
string(FIND "${C}" "${SIG_END}" SEND)
if(SSTART EQUAL -1 OR SEND EQUAL -1 OR SEND LESS SSTART)
  message(FATAL_ERROR "Could not locate SignalColour implementation")
endif()
set(SIG_CODE [===[
wxColour ChartInspectorPi::SignalColour(const wxString &value) const {
  long code = 0;
  wxString token = value.BeforeFirst(',');
  token.Trim(true);
  token.Trim(false);
  if (!token.ToLong(&code)) {
    const int open = token.Find('(', true);
    const int close = token.Find(')', true);
    if (open != wxNOT_FOUND && close > open)
      token.Mid(open + 1, close - open - 1).ToLong(&code);
  }
  if (code == 0) {
    const wxString name = token.Lower();
    if (name.Find("white") != wxNOT_FOUND) code = 1;
    else if (name.Find("black") != wxNOT_FOUND) code = 2;
    else if (name.Find("red") != wxNOT_FOUND) code = 3;
    else if (name.Find("green") != wxNOT_FOUND) code = 4;
    else if (name.Find("blue") != wxNOT_FOUND) code = 5;
    else if (name.Find("yellow") != wxNOT_FOUND) code = 6;
    else if (name.Find("grey") != wxNOT_FOUND ||
             name.Find("gray") != wxNOT_FOUND) code = 7;
    else if (name.Find("brown") != wxNOT_FOUND) code = 8;
    else if (name.Find("amber") != wxNOT_FOUND) code = 9;
    else if (name.Find("violet") != wxNOT_FOUND) code = 10;
    else if (name.Find("orange") != wxNOT_FOUND) code = 11;
    else if (name.Find("magenta") != wxNOT_FOUND) code = 12;
    else if (name.Find("pink") != wxNOT_FOUND) code = 13;
  }

  wxColour c(210, 210, 210);
  switch (code) {
    case 1: c = wxColour(245, 245, 235); break;
    case 2: c = wxColour(25, 25, 25); break;
    case 3: c = wxColour(235, 55, 55); break;
    case 4: c = wxColour(45, 190, 85); break;
    case 5: c = wxColour(55, 120, 235); break;
    case 6: c = wxColour(245, 210, 40); break;
    case 7: c = wxColour(130, 130, 130); break;
    case 8: c = wxColour(145, 95, 55); break;
    case 9: c = wxColour(255, 175, 35); break;
    case 10: c = wxColour(145, 80, 190); break;
    case 11: c = wxColour(245, 125, 35); break;
    case 12: c = wxColour(220, 55, 180); break;
    case 13: c = wxColour(245, 135, 170); break;
    default: break;
  }
  double factor = 1.0;
  if (m_colorScheme == PI_GLOBAL_COLOR_SCHEME_DUSK) factor = 0.78;
  if (m_colorScheme == PI_GLOBAL_COLOR_SCHEME_NIGHT) factor = 0.58;
  return wxColour(static_cast<unsigned char>(c.Red() * factor),
                  static_cast<unsigned char>(c.Green() * factor),
                  static_cast<unsigned char>(c.Blue() * factor));
}

]===])
string(SUBSTRING "${C}" 0 ${SSTART} SPRE)
string(SUBSTRING "${C}" ${SEND} -1 SPOST)
set(C "${SPRE}${SIG_CODE}${SPOST}")

# -----------------------------------------------------------------------------
# Clean decoded colour strings. Providers may return numeric codes, names with
# code suffixes (Green(4)), or imperfect multi-value renderings. Canonicalise
# to unique human-readable colour names.
# -----------------------------------------------------------------------------
set(COL_OLD [===[
static wxString CI_DecodeColours(const wxString &rawValue) {
  wxString result;
  wxStringTokenizer values(rawValue, ",", wxTOKEN_STRTOK);
  while (values.HasMoreTokens()) {
    wxString token = values.GetNextToken();
    token.Trim(true);
    token.Trim(false);
    long code = 0;
    wxString name;
    if (token.ToLong(&code)) name = CI_ColourName(code);
    if (name.IsEmpty()) name = CI_CleanDecodedCodes(token);
    if (name.IsEmpty()) continue;
    if (!result.IsEmpty()) result += ", ";
    result += name;
  }
  return result;
}
]===])
set(COL_NEW [===[
static wxString CI_DecodeColours(const wxString &rawValue) {
  std::vector<wxString> names;
  auto addUnique = [&](const wxString &name) {
    if (name.IsEmpty()) return;
    for (const auto &existing : names)
      if (existing.CmpNoCase(name) == 0) return;
    names.push_back(name);
  };

  wxStringTokenizer values(rawValue, ",", wxTOKEN_STRTOK);
  while (values.HasMoreTokens()) {
    wxString token = values.GetNextToken();
    token.Trim(true);
    token.Trim(false);
    long code = 0;
    wxString name;
    if (token.ToLong(&code)) name = CI_ColourName(code);
    if (name.IsEmpty()) {
      const int open = token.Find('(', true);
      const int close = token.Find(')', true);
      if (open != wxNOT_FOUND && close > open &&
          token.Mid(open + 1, close - open - 1).ToLong(&code))
        name = CI_ColourName(code);
    }
    if (name.IsEmpty()) {
      const wxString lower = token.Lower();
      if (lower.Find("white") != wxNOT_FOUND) name = "White";
      else if (lower.Find("black") != wxNOT_FOUND) name = "Black";
      else if (lower.Find("red") != wxNOT_FOUND) name = "Red";
      else if (lower.Find("green") != wxNOT_FOUND) name = "Green";
      else if (lower.Find("blue") != wxNOT_FOUND) name = "Blue";
      else if (lower.Find("yellow") != wxNOT_FOUND) name = "Yellow";
      else if (lower.Find("grey") != wxNOT_FOUND ||
               lower.Find("gray") != wxNOT_FOUND) name = "Grey";
      else if (lower.Find("brown") != wxNOT_FOUND) name = "Brown";
      else if (lower.Find("amber") != wxNOT_FOUND) name = "Amber";
      else if (lower.Find("violet") != wxNOT_FOUND) name = "Violet";
      else if (lower.Find("orange") != wxNOT_FOUND) name = "Orange";
      else if (lower.Find("magenta") != wxNOT_FOUND) name = "Magenta";
      else if (lower.Find("pink") != wxNOT_FOUND) name = "Pink";
    }
    if (name.IsEmpty()) name = CI_CleanDecodedCodes(token);
    addUnique(name);
  }

  wxString result;
  for (const auto &name : names) {
    if (!result.IsEmpty()) result += ", ";
    result += name;
  }
  return result;
}

static bool CI_DecodeTrailingCode(const wxString &raw, long *code) {
  if (!code) return false;
  wxString token = raw;
  token.Trim(true);
  token.Trim(false);
  if (token.ToLong(code)) return true;
  const int open = token.Find('(', true);
  const int close = token.Find(')', true);
  return open != wxNOT_FOUND && close > open &&
         token.Mid(open + 1, close - open - 1).ToLong(code);
}

static wxString CI_LightAbbreviation(const wxString &raw) {
  long code = 0;
  if (!CI_DecodeTrailingCode(raw, &code)) {
    wxString cleaned = CI_CleanDecodedCodes(raw);
    if (cleaned.Upper().StartsWith("FL")) return "Fl";
    return cleaned;
  }
  switch (code) {
    case 1: return "F";
    case 2: return "Fl";
    case 3: return "LFl";
    case 4: return "Q";
    case 5: return "VQ";
    case 6: return "UQ";
    case 7: return "Iso";
    case 8: return "Oc";
    case 9: return "IQ";
    case 10: return "IVQ";
    case 11: return "IUQ";
    case 12: return "Mo";
    case 13: return "F.Fl";
    case 14: return "Fl.LFl";
    case 28: return "Al";
    case 29: return "F.Al.Fl";
    default: return CI_CleanDecodedCodes(raw);
  }
}

static wxString CI_LightColourAbbreviation(const wxString &raw) {
  const wxString colour = CI_DecodeColours(raw).BeforeFirst(',').Lower();
  if (colour == "white") return "W";
  if (colour == "red") return "R";
  if (colour == "green") return "G";
  if (colour == "blue") return "Bu";
  if (colour == "yellow") return "Y";
  return wxEmptyString;
}

static wxString CI_LightSummary(const S57Catalog &catalog,
                                const wxString &attributes) {
  const wxString chr = catalog.RawAttributeValue(attributes, "LITCHR");
  const wxString grp = catalog.RawAttributeValue(attributes, "SIGGRP");
  const wxString col = catalog.RawAttributeValue(attributes, "COLOUR");
  const wxString per = catalog.RawAttributeValue(attributes, "SIGPER");

  wxString result = CI_LightAbbreviation(chr);
  if (!grp.IsEmpty() && grp != "()" && grp != "(1)" && grp != "1") {
    if (grp.StartsWith("(")) result += grp;
    else result += "(" + CI_CleanDecodedCodes(grp) + ")";
  }
  const wxString colour = CI_LightColourAbbreviation(col);
  if (!colour.IsEmpty()) result += " " + colour;
  double seconds = 0.0;
  if (CI_ParseNumber(per, &seconds))
    result += " " + wxString::Format("%g s", seconds);
  return result;
}

static wxString CI_MetresAndFeet(const wxString &raw) {
  double metres = 0.0;
  if (!CI_ParseNumber(raw, &metres)) return CI_CleanDecodedCodes(raw);
  const long feet = static_cast<long>(std::lround(metres * 3.280839895));
  return wxString::Format("%g m / %ld ft", metres, feet);
}
]===])
string(FIND "${C}" "${COL_OLD}" COLPOS)
if(COLPOS EQUAL -1)
  message(FATAL_ERROR "Could not locate CI_DecodeColours")
endif()
string(REPLACE "${COL_OLD}" "${COL_NEW}" C "${C}")

# -----------------------------------------------------------------------------
# Update the hover window signature and add an associated-light section to the
# same property grid. The selected aid's colour and the light colour stay
# separate. Colour chips are generated from canonical names, not provider raw
# strings.
# -----------------------------------------------------------------------------
set(FSIG_OLD [===[
void ChartInspectorPi::UpdateHoverInfoPanel(const wxString &feature,
                                            const wxString &objectName,
                                            const wxString &attributes,
                                            int geometryType) {
]===])
set(FSIG_NEW [===[
void ChartInspectorPi::UpdateHoverInfoPanel(
    const wxString &feature, const wxString &objectName,
    const wxString &attributes, int geometryType,
    const wxString &associatedLightAttributes) {
]===])
string(FIND "${C}" "${FSIG_OLD}" FPOS)
if(FPOS EQUAL -1)
  message(FATAL_ERROR "Could not locate UpdateHoverInfoPanel definition")
endif()
string(REPLACE "${FSIG_OLD}" "${FSIG_NEW}" C "${C}")

set(ROW_OLD [===[
      std::vector<wxColour> colourChips;
      if (label == "Color" && !colourRaw.IsEmpty()) {
        wxStringTokenizer colours(colourRaw, ",", wxTOKEN_STRTOK);
        while (colours.HasMoreTokens()) {
          wxString token = colours.GetNextToken();
          token.Trim(true);
          token.Trim(false);
          colourChips.push_back(SignalColour(token));
        }
      }
      CI_AddPropertyRow(m_hoverInfoDetails, grid, label, value, colourChips);
    }
    m_hoverInfoDetails->Show(grid->GetItemCount() > 0);
    m_hoverInfoDetails->Layout();
]===])
set(ROW_NEW [===[
      std::vector<wxColour> colourChips;
      if (label == "Color") {
        wxStringTokenizer colours(value, ",", wxTOKEN_STRTOK);
        while (colours.HasMoreTokens()) {
          wxString token = colours.GetNextToken();
          token.Trim(true);
          token.Trim(false);
          if (!token.IsEmpty()) colourChips.push_back(SignalColour(token));
        }
      }
      CI_AddPropertyRow(m_hoverInfoDetails, grid, label, value, colourChips);
    }

    if (!associatedLightAttributes.IsEmpty()) {
      const wxString lightColourRaw =
          m_s57Catalog.RawAttributeValue(associatedLightAttributes, "COLOUR");
      const wxString lightColour = CI_DecodeColours(lightColourRaw);
      std::vector<wxColour> lightChips;
      wxStringTokenizer colours(lightColour, ",", wxTOKEN_STRTOK);
      while (colours.HasMoreTokens()) {
        wxString token = colours.GetNextToken();
        token.Trim(true);
        token.Trim(false);
        if (!token.IsEmpty()) lightChips.push_back(SignalColour(token));
      }

      const wxString summary =
          CI_LightSummary(m_s57Catalog, associatedLightAttributes);
      CI_AddPropertyRow(m_hoverInfoDetails, grid, "Light", summary, lightChips);

      const wxString height =
          m_s57Catalog.RawAttributeValue(associatedLightAttributes, "HEIGHT");
      if (!height.IsEmpty())
        CI_AddPropertyRow(m_hoverInfoDetails, grid, "Light height",
                          CI_MetresAndFeet(height));

      const wxString range =
          m_s57Catalog.RawAttributeValue(associatedLightAttributes, "VALNMR");
      double nm = 0.0;
      if (CI_ParseNumber(range, &nm))
        CI_AddPropertyRow(m_hoverInfoDetails, grid, "Nominal range",
                          wxString::Format("%g NM", nm));
    }

    m_hoverInfoDetails->Show(grid->GetItemCount() > 0);
    m_hoverInfoDetails->Layout();
]===])
string(FIND "${C}" "${ROW_OLD}" RPOS)
if(RPOS EQUAL -1)
  message(FATAL_ERROR "Could not locate property-grid row loop")
endif()
string(REPLACE "${ROW_OLD}" "${ROW_NEW}" C "${C}")

# -----------------------------------------------------------------------------
# Once the selected buoy/beacon is known, issue one small attributes-enabled
# vector query centered on the selected point for LIGHTS. This runs only when
# the selected hover object changes, just like the full geometry/details query.
# -----------------------------------------------------------------------------
set(CALL_OLD [===[
      if (!details.points.empty()) {
        best = details;
        UpdateHoverInfoPanel(details.feature, details.objectName,
                             details.attributes,
                             static_cast<int>(details.geometry));
        m_hoverInfoKey = key;
]===])
set(CALL_NEW [===[
      if (!details.points.empty()) {
        best = details;
        wxString associatedLightAttributes;
        if (details.geometry == 1 &&
            (details.feature.StartsWith("BOY") ||
             details.feature.StartsWith("BCN"))) {
          CI_HoverCandidate light;
          light.cursorLat = details.points[0].lat;
          light.cursorLon = details.points[0].lon;
          light.includeFilter = "LIGHTS";
          PI_VectorQueryV1 lightQuery = q;
          lightQuery.lat = light.cursorLat;
          lightQuery.lon = light.cursorLon;
          lightQuery.search_radius_pixels =
              std::max(8.0, static_cast<double>(m_hitRadiusPixels));
          lightQuery.flags &= ~CI_SKIP_ATTRIBUTES;
          lightQuery.geometry_mask = 1u;
          lightQuery.max_objects = 8;
          lightQuery.max_points_per_object = 16;
          queryFn(0, &lightQuery, CI_CollectHover, &light);
          if (light.feature == "LIGHTS" && !light.attributes.IsEmpty())
            associatedLightAttributes = light.attributes;
        }
        UpdateHoverInfoPanel(details.feature, details.objectName,
                             details.attributes,
                             static_cast<int>(details.geometry),
                             associatedLightAttributes);
        m_hoverInfoKey = key;
]===])
string(FIND "${C}" "${CALL_OLD}" QPOS)
if(QPOS EQUAL -1)
  message(FATAL_ERROR "Could not locate hover detail display call")
endif()
string(REPLACE "${CALL_OLD}" "${CALL_NEW}" C "${C}")

file(WRITE "${CPP}" "${C}")
message(STATUS "Installed Chart Inspector associated light/colours v1")
message(STATUS "  decoded colour names now drive correctly coloured chips")
message(STATUS "  duplicate/code suffixes are removed from colour text")
message(STATUS "  buoy/beacon hover queries co-located LIGHTS once per object")
message(STATUS "  light summary shows characteristic, group, colour and period")
message(STATUS "  light height and nominal range are restored in the property grid")
