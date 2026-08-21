#include "chartinspector_pi.h"
#include "ui/app_style.h"
#include "ui/rounded_panel.h"

#ifdef _WIN32
#include <windows.h>
#endif

#include <algorithm>
#include <cmath>
#include <vector>

#include <GL/gl.h>
#include <wx/checklst.h>
#include <wx/dcbuffer.h>
#include <wx/dcclient.h>
#include <wx/fileconf.h>
#include <wx/spinctrl.h>
#include <wx/statline.h>
#include <wx/timer.h>
#include <wx/tokenzr.h>

namespace {
// CHARTINSPECTOR_VECTOR_HOVER_V1
struct CI_VectorQueryV1 {
  uint32_t struct_size; double lat; double lon; double search_radius_pixels;
  uint32_t flags; uint32_t geometry_mask; uint32_t max_objects;
  uint32_t max_points_per_object; const char *exclude_feature_classes_utf8;
};
struct CI_VectorPositionV1 { double lat; double lon; };
struct CI_VectorPartV1 { uint32_t first_point; uint32_t point_count; };
struct CI_VectorAttributeV1 { const char *name_utf8; const char *value_utf8; };
struct CI_VectorObjectV1 {
  uint32_t struct_size; uint32_t geometry_type; const char *feature_class_utf8;
  const char *object_name_utf8; const CI_VectorPositionV1 *points;
  uint32_t point_count; const CI_VectorPartV1 *parts; uint32_t part_count;
  const CI_VectorAttributeV1 *attributes; uint32_t attribute_count;
};
using CI_VectorSinkV1 = bool (*)(const CI_VectorObjectV1 *, void *);
using CI_QueryVectorV1 = bool (*)(int, const CI_VectorQueryV1 *, CI_VectorSinkV1, void *);
constexpr uint32_t CI_SKIP_ATTRIBUTES = 1u;
constexpr uint32_t CI_INCLUDE_NON_RENDERED = 1u << 1;
constexpr uint32_t CI_PREFER_DETAILED_CHART = 1u << 2;
constexpr uint32_t CI_GEOMETRY_ALL = 7u;

struct CI_HoverPosition { double lat = 0.0; double lon = 0.0; };
struct CI_HoverPart { unsigned int firstPoint = 0; unsigned int pointCount = 0; };
// CHARTINSPECTOR_HOVER_NEAREST_V1
struct CI_HoverCandidate {
  uint32_t geometry = 0;
  wxString feature;
  std::vector<CI_HoverPosition> points;
  std::vector<CI_HoverPart> parts;
  int score = -100000;
  double cursorLat = 0.0;
  double cursorLon = 0.0;
  double distanceMetres = 1.0e100;
  wxString objectName;
  wxString attributes;
  wxString includeFilter;
};

static double CI_DistancePointSegmentMetres(double qlat, double qlon,
                                             double alat, double alon,
                                             double blat, double blon) {
  const double kLatM = 111319.49079327357;
  const double cosLat = std::max(0.01, std::cos(qlat * 3.14159265358979323846 / 180.0));
  const double kLonM = kLatM * cosLat;
  const double ax = (alon - qlon) * kLonM;
  const double ay = (alat - qlat) * kLatM;
  const double bx = (blon - qlon) * kLonM;
  const double by = (blat - qlat) * kLatM;
  const double vx = bx - ax;
  const double vy = by - ay;
  const double vv = vx * vx + vy * vy;
  double t = vv > 1.0e-12 ? -(ax * vx + ay * vy) / vv : 0.0;
  t = std::max(0.0, std::min(1.0, t));
  const double x = ax + t * vx;
  const double y = ay + t * vy;
  return std::sqrt(x * x + y * y);
}

static double CI_ObjectDistanceMetres(const CI_VectorObjectV1 *o,
                                      double qlat, double qlon) {
  if (!o || !o->points || !o->point_count) return 1.0e100;
  if (o->geometry_type == 1 || o->point_count == 1) {
    const double dy = (o->points[0].lat - qlat) * 111319.49079327357;
    const double dx = (o->points[0].lon - qlon) * 111319.49079327357 *
                      std::max(0.01, std::cos(qlat * 3.14159265358979323846 / 180.0));
    return std::sqrt(dx * dx + dy * dy);
  }

  double best = 1.0e100;
  if (o->parts && o->part_count) {
    for (uint32_t p = 0; p < o->part_count; ++p) {
      const uint32_t first = o->parts[p].first_point;
      const uint32_t count = o->parts[p].point_count;
      if (count < 2 || first >= o->point_count) continue;
      const uint32_t end = std::min<uint32_t>(o->point_count, first + count);
      for (uint32_t i = first + 1; i < end; ++i) {
        best = std::min(best, CI_DistancePointSegmentMetres(
            qlat, qlon, o->points[i - 1].lat, o->points[i - 1].lon,
            o->points[i].lat, o->points[i].lon));
      }
    }
  } else {
    for (uint32_t i = 1; i < o->point_count; ++i) {
      best = std::min(best, CI_DistancePointSegmentMetres(
          qlat, qlon, o->points[i - 1].lat, o->points[i - 1].lon,
          o->points[i].lat, o->points[i].lon));
    }
  }
  return best;
}

// CHARTINSPECTOR_SELECTABLE_POLICY_V2
static bool CI_FeatureMatchesHoverFilter(const wxString &feature,
                                         const wxString &filter) {
  if (feature.IsEmpty() || filter.IsEmpty()) return false;
  const wxString candidate = feature.Upper();
  wxStringTokenizer tokens(filter, ",; \t\r\n", wxTOKEN_STRTOK);
  while (tokens.HasMoreTokens()) {
    wxString token = tokens.GetNextToken().Upper();
    token.Trim(true);
    token.Trim(false);
    if (token.IsEmpty()) continue;
    if (token.EndsWith("*")) {
      token.RemoveLast();
      if (!token.IsEmpty() && candidate.StartsWith(token)) return true;
    } else if (candidate == token) {
      return true;
    }
  }
  return false;
}

int CI_FeatureScore(const wxString &f, uint32_t geometry) {
  if (f.StartsWith("BOY") || f.StartsWith("BCN") || f == "LIGHTS" ||
      f == "WRECKS" || f == "UWTROC" || f == "OBSTRN") return 400;
  if (geometry == 1) return 300;
  if (geometry == 2) return 200;
  return 100;
}

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

bool CI_CollectHover(const CI_VectorObjectV1 *o, void *user) {
  if (!o || !user || !o->points || !o->point_count) return true;
  auto *best = static_cast<CI_HoverCandidate *>(user);
  const wxString feature = wxString::FromUTF8(o->feature_class_utf8 ? o->feature_class_utf8 : "").Upper();
  if (!CI_FeatureMatchesHoverFilter(feature, best->includeFilter)) return true;
  const int score = CI_FeatureScore(feature, o->geometry_type);
  const double distance = CI_ObjectDistanceMetres(o, best->cursorLat, best->cursorLon);
  // Semantic priority remains useful (buoys/lights/points before generic
  // areas), but candidates with equal priority are now ordered by the actual
  // distance from the cursor to their returned geometry rather than provider
  // iteration order.
  if (score < best->score ||
      (score == best->score && distance >= best->distanceMetres)) return true;
  CI_HoverCandidate next;
  next.geometry = o->geometry_type; next.feature = feature; next.score = score;
  next.cursorLat = best->cursorLat; next.cursorLon = best->cursorLon;
  next.distanceMetres = distance;
  next.includeFilter = best->includeFilter;
  next.objectName =
      wxString::FromUTF8(o->object_name_utf8 ? o->object_name_utf8 : "");
  for (uint32_t i = 0; o->attributes && i < o->attribute_count; ++i) {
    const char *name = o->attributes[i].name_utf8;
    const char *value = o->attributes[i].value_utf8;
    if (!name || !*name) continue;
    if (!next.attributes.IsEmpty()) next.attributes += "\n";
    next.attributes += wxString::FromUTF8(name);
    next.attributes += "=";
    next.attributes += wxString::FromUTF8(value ? value : "");
  }
  for (uint32_t i = 0; i < o->point_count; ++i)
    next.points.push_back({o->points[i].lat, o->points[i].lon});
  for (uint32_t i = 0; i < o->part_count; ++i)
    next.parts.push_back({o->parts[i].first_point, o->parts[i].point_count});
  *best = next;
  return true;
}

static bool CI_CollectHiddenNavigationHover(const CI_VectorObjectV1 *o,
                                            void *user) {
  if (!o) return true;
  const wxString feature =
      wxString::FromUTF8(o->feature_class_utf8 ? o->feature_class_utf8 : "")
          .Upper();
  if (!CI_IsHiddenNavigationFeature(feature)) return true;
  return CI_CollectHover(o, user);
}
wxString FilterRawAttributes(const wxString &raw,
                             const std::vector<wxString> &excluded) {
  wxString result;
  wxStringTokenizer lines(raw, "\n", wxTOKEN_STRTOK);
  while (lines.HasMoreTokens()) {
    wxString line = lines.GetNextToken();
    const int equals = line.Find('=');
    if (equals == wxNOT_FOUND) continue;
    wxString acronym = line.Left(equals).Upper();
    acronym.Trim(true);
    acronym.Trim(false);
    bool skip = false;
    for (const auto &item : excluded) {
      if (acronym == item) {
        skip = true;
        break;
      }
    }
    if (skip) continue;
    if (!result.IsEmpty()) result += "\n";
    result += line;
  }
  return result;
}

void AppendInfoLine(wxString *target, const wxString &label,
                    const wxString &value) {
  if (!target || value.IsEmpty()) return;
  if (!target->IsEmpty()) *target += "\n";
  *target += label + ": " + value;
}

wxString MetresAndFeet(const wxString &raw) {
  double metres = 0.0;
  if (!raw.ToDouble(&metres)) return raw;
  const long feet = static_cast<long>(std::lround(metres * 3.280839895));
  return wxString::Format("%g m / %ld ft", metres, feet);
}
}  // namespace

extern "C" DECL_EXP opencpn_plugin *create_pi(void *ppimgr) {
  return new ChartInspectorPi(ppimgr);
}

extern "C" DECL_EXP void destroy_pi(opencpn_plugin *plugin) { delete plugin; }

ChartInspectorPi::ChartInspectorPi(void *ppimgr) : opencpn_plugin_118(ppimgr) {}

int ChartInspectorPi::Init() {
#ifdef _WIN32
  HMODULE host = GetModuleHandleW(nullptr);
  if (host) {
    m_hitTestV4 = reinterpret_cast<HitTestV3Fn>(
        GetProcAddress(host, "OCPNChartInspectorHitTestV4"));
    m_hitTestV3 = reinterpret_cast<HitTestV3Fn>(
        GetProcAddress(host, "OCPNChartInspectorHitTestV3"));
    m_hitTestV2 = reinterpret_cast<HitTestV2Fn>(
        GetProcAddress(host, "OCPNChartInspectorHitTestV2"));
    m_hitTest = reinterpret_cast<HitTestFn>(
        GetProcAddress(host, "OCPNChartInspectorHitTest"));
  }
#endif

  wxString *sharedData = GetpSharedDataLocation();
  if (sharedData) m_s57Catalog.Load(*sharedData);

  m_config = GetOCPNConfigObject();
  LoadConfig();
  BuildToolbarBitmaps();
  m_pluginBitmap = m_enabled ? m_toolbarEnabledBitmap : m_toolbarDisabledBitmap;
  m_toolbarId = InsertPlugInTool(
      "Chart Inspector", &m_pluginBitmap, &m_pluginBitmap, wxITEM_CHECK,
      "Chart Inspector", "Enable or disable chart object inspection", nullptr,
      -1, 0, this);
  UpdateToolbarVisual();

  return WANTS_MOUSE_EVENTS | WANTS_CURSOR_LATLON | WANTS_OVERLAY_CALLBACK |
         WANTS_OPENGL_OVERLAY_CALLBACK | WANTS_TOOLBAR_CALLBACK |
         INSTALLS_TOOLBAR_TOOL | WANTS_PREFERENCES | WANTS_CONFIG;
}

bool ChartInspectorPi::DeInit() {
  SaveConfig();
  StopLightPreview();
  if (m_toolbarId >= 0) RemovePlugInTool(m_toolbarId);
  m_toolbarId = -1;
  if (m_infoPanel) m_infoPanel->Destroy();
  m_infoPanel = nullptr;
  if (m_hoverInfoWindow) m_hoverInfoWindow->Destroy();
  m_hoverInfoWindow = nullptr;
  m_hoverInfoTitle = nullptr;
  m_hoverInfoMeta = nullptr;
  m_hoverInfoDetails = nullptr;
  m_hoverInfoGrid = nullptr;
  m_hoverInfoBody = nullptr;
  return true;
}

int ChartInspectorPi::GetAPIVersionMajor() { return 1; }
int ChartInspectorPi::GetAPIVersionMinor() { return 18; }
int ChartInspectorPi::GetPlugInVersionMajor() { return 0; }
int ChartInspectorPi::GetPlugInVersionMinor() { return 8; }
int ChartInspectorPi::GetToolbarToolCount() { return 1; }

wxBitmap *ChartInspectorPi::GetPlugInBitmap() { return &m_pluginBitmap; }
wxString ChartInspectorPi::GetCommonName() { return "Chart Inspector"; }
wxString ChartInspectorPi::GetShortDescription() {
  return "Interactive inspection of vector chart objects.";
}
wxString ChartInspectorPi::GetLongDescription() {
  return "Chart Inspector highlights configured vector chart features near the "
         "cursor and shows readable S-57 object information on click.";
}

void ChartInspectorPi::BuildToolbarBitmaps() {
  auto build = [](const wxColour &colour, bool active) {
    wxBitmap bitmap(24, 24);
    wxMemoryDC dc(bitmap);
    dc.SetBackground(wxBrush(wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOW)));
    dc.Clear();
    dc.SetPen(wxPen(colour, active ? 3 : 2));
    dc.SetBrush(active ? wxBrush(colour) : *wxTRANSPARENT_BRUSH);
    dc.DrawCircle(wxPoint(9, 9), 5);
    dc.SetBrush(*wxTRANSPARENT_BRUSH);
    dc.DrawLine(13, 13, 21, 21);
    dc.SelectObject(wxNullBitmap);
    return bitmap;
  };
  m_toolbarEnabledBitmap = build(wxColour(0, 210, 235), true);
  m_toolbarDisabledBitmap = build(wxColour(115, 115, 115), false);
}

void ChartInspectorPi::UpdateToolbarVisual() {
  if (m_toolbarId < 0) return;
  wxBitmap *bitmap = m_enabled ? &m_toolbarEnabledBitmap : &m_toolbarDisabledBitmap;
  SetToolbarToolBitmaps(m_toolbarId, bitmap, bitmap);
  SetToolbarItemState(m_toolbarId, m_enabled);
}

void ChartInspectorPi::ApplyInfoTheme() {
  if (!m_infoPanel) return;
  wxColour background = wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOW);
  wxColour foreground = wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOWTEXT);
  wxColour secondary = wxSystemSettings::GetColour(wxSYS_COLOUR_GRAYTEXT);
  GetGlobalColor("DILG0", &background);
  GetGlobalColor("DILG4", &foreground);
  GetGlobalColor("DILG3", &secondary);
  m_infoPanel->SetBackgroundColour(background);
  m_infoPanel->SetForegroundColour(foreground);
  if (m_infoVisual) {
    m_infoVisual->SetBackgroundColour(background);
    m_infoVisual->SetForegroundColour(foreground);
  }
  if (m_infoTitle) m_infoTitle->SetForegroundColour(foreground);
  if (m_infoSubtitle) m_infoSubtitle->SetForegroundColour(foreground);
  if (m_infoAcronym) m_infoAcronym->SetForegroundColour(secondary);
  if (m_infoBody) m_infoBody->SetForegroundColour(foreground);
  if (m_infoTechnical) m_infoTechnical->SetForegroundColour(secondary);
  if (m_infoVisual) {
    const wxWindowList &children = m_infoVisual->GetChildren();
    for (wxWindowList::const_iterator it = children.begin(); it != children.end();
         ++it) {
      wxWindow *child = *it;
      if (!child || child == m_lightIndicator) continue;
      if (dynamic_cast<wxStaticText *>(child)) {
        child->SetBackgroundColour(background);
        child->SetForegroundColour(foreground);
      }
    }
  }
  if (m_lightIndicator) m_lightIndicator->SetBackgroundColour(background);
  m_infoPanel->Refresh();
}

void ChartInspectorPi::LoadConfig() {
  if (!m_config) return;
  m_config->SetPath("/PlugIns/ChartInspector");
  m_config->Read("Enabled", &m_enabled, true);
  m_config->Read("ShowTechnicalData", &m_showTechnicalData, false);
  m_config->Read("IncludeScaleHidden", &m_includeScaleHidden, false);
  long radius = 5;
  m_config->Read("HitRadiusPixels", &radius, 5L);
  m_hitRadiusPixels = static_cast<int>(std::max(2L, std::min(20L, radius)));
  const wxString defaultSelectable =
      "BOY*,BCN*,LIGHTS,TOPMAR,DAYMAR,WRECKS,UWTROC,OBSTRN,LNDMRK,"
      "BUISGL,SILTNK,BRIDGE,CRANES,FLODOC,GATCON,DAMCON,HRBFAC,BERTHS,"
      "MORFAC,OFSPLF,PILPNT,CBLSUB,PIPARE,PIPSOL,TUNNEL,RTPBCN,RADSTA,"
      "RSCSTA,FORSTC,CAUSWY,DYKCON";
  m_config->Read("FeatureFilter", &m_featureFilter, defaultSelectable);
  if (m_featureFilter == "BOY*,BCN*,LIGHTS,WRECKS,UWTROC,OBSTRN")
    m_featureFilter = defaultSelectable;
}

void ChartInspectorPi::SaveConfig() {
  if (!m_config) return;
  m_config->SetPath("/PlugIns/ChartInspector");
  m_config->Write("Enabled", m_enabled);
  m_config->Write("ShowTechnicalData", m_showTechnicalData);
  m_config->Write("IncludeScaleHidden", m_includeScaleHidden);
  m_config->Write("HitRadiusPixels", static_cast<long>(m_hitRadiusPixels));
  m_config->Write("FeatureFilter", m_featureFilter);
  m_config->Flush();
}

void ChartInspectorPi::SetCursorLatLon(double lat, double lon) {
  m_cursorLat = lat;
  m_cursorLon = lon;
  m_hasCursorPosition = true;
}

void ChartInspectorPi::SetColorScheme(PI_ColorScheme cs) {
  m_colorScheme = cs;
  ApplyInfoTheme();
  ApplyHoverWindowTheme();
  if (m_infoPanel && m_infoPanel->IsShown()) {
    BuildVisualSummary();
    ApplyInfoTheme();
    m_infoPanel->Layout();
    m_infoPanel->Refresh();
  }
}

// CHARTINSPECTOR_SIMPLE_HOVER_WINDOW_V1
// CHARTINSPECTOR_NAVIGATION_INFO_V1
// CHARTINSPECTOR_NAV_DEPTH_BUILD_FIX_V1
// CHARTINSPECTOR_PROPERTY_GRID_V1
namespace {

struct CI_RawAttribute {
  wxString acronym;
  wxString value;
};

static std::vector<CI_RawAttribute> CI_ParseRawAttributes(
    const wxString &attributes) {
  std::vector<CI_RawAttribute> result;
  wxStringTokenizer lines(attributes, "\n", wxTOKEN_STRTOK);
  while (lines.HasMoreTokens()) {
    wxString line = lines.GetNextToken();
    line.Trim(true);
    line.Trim(false);
    if (line.IsEmpty()) continue;
    const int equals = line.Find('=');
    if (equals == wxNOT_FOUND) continue;
    wxString acronym = line.Left(equals).Upper();
    wxString value = line.Mid(equals + 1);
    acronym.Trim(true);
    acronym.Trim(false);
    value.Trim(true);
    value.Trim(false);
    if (!acronym.IsEmpty()) result.push_back({acronym, value});
  }
  return result;
}

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

static wxString CI_UserDepth(double metres) {
  return wxString::Format("%g m", metres);
}

static wxString CI_MetricLength(const wxString &label,
                                const wxString &rawValue) {
  double metres = 0.0;
  if (!CI_ParseNumber(rawValue, &metres)) return wxEmptyString;
  return label + ": " + wxString::Format("%g m", metres);
}

static wxString CI_DepthLike(const wxString &label,
                             const wxString &rawValue) {
  double metres = 0.0;
  if (!CI_ParseNumber(rawValue, &metres))
    return label + ": " + rawValue;
  return label + ": " + CI_UserDepth(metres);
}

static wxString CI_CleanDecodedCodes(const wxString &input) {
  wxString out;
  for (size_t i = 0; i < input.length();) {
    if (input[i] == '(') {
      size_t j = i + 1;
      bool hasDigit = false;
      while (j < input.length() && input[j] >= '0' && input[j] <= '9') {
        hasDigit = true;
        ++j;
      }
      if (hasDigit && j < input.length() && input[j] == ')') {
        i = j + 1;
        continue;
      }
    }
    out += input[i++];
  }
  while (out.Replace("  ", " ")) {}
  out.Replace(" ,", ",");
  out.Trim(true);
  out.Trim(false);
  while (out.EndsWith(";")) {
    out.RemoveLast();
    out.Trim(true);
  }
  return out;
}

static wxString CI_ColourName(long code) {
  switch (code) {
    case 1: return "White";
    case 2: return "Black";
    case 3: return "Red";
    case 4: return "Green";
    case 5: return "Blue";
    case 6: return "Yellow";
    case 7: return "Grey";
    case 8: return "Brown";
    case 9: return "Amber";
    case 10: return "Violet";
    case 11: return "Orange";
    case 12: return "Magenta";
    case 13: return "Pink";
    default: return wxEmptyString;
  }
}

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

static wxString CI_LightCharacteristic(const wxString &rawValue) {
  long code = 0;
  if (!rawValue.ToLong(&code)) return CI_CleanDecodedCodes(rawValue);
  switch (code) {
    case 1: return "Fixed";
    case 2: return "Flashing";
    case 3: return "Long-flashing";
    case 4: return "Quick-flashing";
    case 5: return "Very quick-flashing";
    case 6: return "Ultra quick-flashing";
    case 7: return "Isophase";
    case 8: return "Occulting";
    case 9: return "Interrupted quick-flashing";
    case 10: return "Interrupted very quick-flashing";
    case 11: return "Interrupted ultra quick-flashing";
    case 12: return "Morse";
    case 13: return "Fixed and flashing";
    case 14: return "Flashing and long-flashing";
    case 28: return "Alternating";
    case 29: return "Fixed and alternating flashing";
    default: return CI_CleanDecodedCodes(rawValue);
  }
}

static wxString CI_FriendlyAttribute(const S57Catalog &catalog,
                                     const wxString &acronym,
                                     const wxString &rawValue) {
  if (acronym == "VALSOU") return CI_DepthLike("Depth", rawValue);
  if (acronym == "DRVAL1") return CI_DepthLike("Minimum depth", rawValue);
  if (acronym == "DRVAL2") return CI_DepthLike("Maximum depth", rawValue);
  if (acronym == "VERCLR") return CI_DepthLike("Vertical clearance", rawValue);
  if (acronym == "VERCSA")
    return CI_DepthLike("Safe vertical clearance", rawValue);
  if (acronym == "VERCCL")
    return CI_DepthLike("Closed vertical clearance", rawValue);
  if (acronym == "VERCOP")
    return CI_DepthLike("Open vertical clearance", rawValue);
  if (acronym == "HORCLR") return CI_MetricLength("Horizontal clearance", rawValue);
  if (acronym == "HEIGHT") return CI_MetricLength("Height", rawValue);
  if (acronym == "ELEVAT") return CI_MetricLength("Elevation", rawValue);
  if (acronym == "HORLEN") return CI_MetricLength("Length", rawValue);
  if (acronym == "HORWID") return CI_MetricLength("Width", rawValue);
  if (acronym == "VERLEN") return CI_MetricLength("Vertical length", rawValue);
  if (acronym == "COLOUR") return "Color: " + CI_DecodeColours(rawValue);
  if (acronym == "LITCHR")
    return "Light characteristic: " + CI_LightCharacteristic(rawValue);
  if (acronym == "SIGPER") {
    double seconds = 0.0;
    if (CI_ParseNumber(rawValue, &seconds))
      return "Period: " + wxString::Format("%g s", seconds);
  }
  if (acronym == "VALNMR") {
    double nm = 0.0;
    if (CI_ParseNumber(rawValue, &nm))
      return "Nominal range: " + wxString::Format("%g NM", nm);
  }
  if (acronym == "ORIENT" || acronym == "SECTR1" || acronym == "SECTR2") {
    double degrees = 0.0;
    if (CI_ParseNumber(rawValue, &degrees)) {
      wxString label = acronym == "ORIENT" ? "Orientation" :
                       acronym == "SECTR1" ? "Sector start" : "Sector end";
      return label + ": " + wxString::Format("%g", degrees) +
             wxString::FromUTF8("°");
    }
  }

  return CI_CleanDecodedCodes(
      catalog.FormatAttributes(acronym + "=" + rawValue, nullptr));
}

static int CI_NavigationPriority(const wxString &acronym) {
  if (acronym == "WATLEV" || acronym == "EXPSOU" ||
      acronym == "QUASOU" || acronym == "RESTRN" ||
      acronym == "STATUS")
    return 0;
  if (acronym.StartsWith("CAT") && acronym != "CATGEO") return 1;
  if (acronym == "FUNCTN" || acronym == "CONVIS" || acronym == "NATCON")
    return 1;
  if (acronym == "LITCHR" || acronym == "COLOUR" || acronym == "COLPAT" ||
      acronym == "SIGGRP" || acronym == "SIGPER" || acronym == "VALNMR" ||
      acronym == "ORIENT" || acronym == "SECTR1" || acronym == "SECTR2")
    return 2;
  if (acronym == "HORCLR" || acronym == "HEIGHT" || acronym == "ELEVAT" ||
      acronym == "HORLEN" || acronym == "HORWID" || acronym == "VERLEN")
    return 3;
  if (acronym == "INFORM" || acronym == "NINFOM" ||
      acronym == "DATSTA" || acronym == "DATEND" ||
      acronym == "PERSTA" || acronym == "PEREND")
    return 4;
  return 99;
}

static bool CI_IsPrimaryNavigationAttribute(const wxString &acronym) {
  return acronym == "VALSOU" || acronym == "VERCSA" ||
         acronym == "VERCLR" || acronym == "VERCCL" ||
         acronym == "VERCOP" || acronym == "DRVAL1" ||
         acronym == "DRVAL2";
}

static bool CI_IsTechnicalAttribute(const wxString &acronym) {
  return acronym == "CATGEO" || acronym == "SCAMIN" ||
         acronym == "SCAMAX" || acronym == "SORDAT" ||
         acronym == "SORIND" || acronym == "RECDAT" ||
         acronym == "RECIND" || acronym == "GRUP" ||
         acronym.StartsWith("$");
}

struct CI_NavigationInfo {
  wxString primary;
  wxString details;
  wxString technical;
};

static CI_NavigationInfo CI_BuildNavigationInfo(
    const S57Catalog &catalog, const wxString &feature,
    const wxString &objectName, const wxString &attributes,
    int geometryType, bool showTechnical) {
  CI_NavigationInfo info;
  const auto raw = CI_ParseRawAttributes(attributes);

  static const char *primaryOrder[] = {
      "VALSOU", "VERCSA", "VERCLR", "VERCCL", "VERCOP", "DRVAL1", "DRVAL2"};
  wxString primaryAcronym;
  for (const char *wanted : primaryOrder) {
    for (const auto &attribute : raw) {
      if (attribute.acronym == wanted) {
        info.primary = CI_FriendlyAttribute(catalog, attribute.acronym,
                                            attribute.value);
        primaryAcronym = attribute.acronym;
        break;
      }
    }
    if (!info.primary.IsEmpty()) break;
  }

  for (int priority = 0; priority <= 4; ++priority) {
    for (const auto &attribute : raw) {
      if (attribute.acronym == primaryAcronym ||
          CI_IsPrimaryNavigationAttribute(attribute.acronym) ||
          attribute.acronym == "OBJNAM" || attribute.acronym == "NOBJNM" ||
          CI_IsTechnicalAttribute(attribute.acronym) ||
          CI_NavigationPriority(attribute.acronym) != priority)
        continue;
      const wxString line = CI_FriendlyAttribute(
          catalog, attribute.acronym, attribute.value);
      if (line.IsEmpty()) continue;
      if (!info.details.IsEmpty()) info.details += "\n";
      info.details += line;
    }
  }

  if (!objectName.IsEmpty()) {
    if (!info.details.IsEmpty()) info.details = "Name: " + objectName + "\n" + info.details;
    else info.details = "Name: " + objectName;
  }

  if (showTechnical) {
    const wxString geometry = geometryType == 3 ? "Area" :
                              geometryType == 2 ? "Line" : "Point";
    info.technical = "S-57 class: " + feature + "\nGeometry: " + geometry;
    for (const auto &attribute : raw) {
      if (!CI_IsTechnicalAttribute(attribute.acronym)) continue;
      info.technical += "\n" + attribute.acronym + ": " + attribute.value;
    }
  }

  return info;
}

// CHARTINSPECTOR_PROPERTY_GRID_COLOUR_ACCESS_FIX_V1
static void CI_AddPropertyRow(wxPanel *panel, wxFlexGridSizer *grid,
                              const wxString &label, const wxString &value,
                              const std::vector<wxColour> &colourChips = {}) {
  if (!panel || !grid || value.IsEmpty()) return;

  wxStaticText *name = new wxStaticText(panel, wxID_ANY, label);
  name->SetFont(ci_ui::AppStyle::LabelFont(name->GetFont()));
  name->SetMinSize(wxSize(ci_ui::AppStyle::kLabelColumnWidth, -1));
  name->SetBackgroundColour(panel->GetBackgroundColour());
  name->SetForegroundColour(panel->GetForegroundColour());
  grid->Add(name, 0, wxALIGN_TOP | wxTOP, 1);

  if (!colourChips.empty()) {
    wxBoxSizer *valueRow = new wxBoxSizer(wxHORIZONTAL);
    for (const wxColour &colour : colourChips) {
      wxPanel *chip = new wxPanel(panel, wxID_ANY, wxDefaultPosition,
                                  wxSize(ci_ui::AppStyle::kColorChipSize, ci_ui::AppStyle::kColorChipSize), wxBORDER_SIMPLE);
      chip->SetMinSize(wxSize(ci_ui::AppStyle::kColorChipSize, ci_ui::AppStyle::kColorChipSize));
      chip->SetBackgroundColour(colour);
      valueRow->Add(chip, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 5);
    }
    wxStaticText *valueText = new wxStaticText(panel, wxID_ANY, value);
    valueText->SetBackgroundColour(panel->GetBackgroundColour());
    valueText->SetForegroundColour(panel->GetForegroundColour());
    valueRow->Add(valueText, 0, wxALIGN_CENTER_VERTICAL);
    grid->Add(valueRow, 1, wxEXPAND);
  } else {
    wxStaticText *text = new wxStaticText(panel, wxID_ANY, value);
    text->SetBackgroundColour(panel->GetBackgroundColour());
    text->SetForegroundColour(panel->GetForegroundColour());
    grid->Add(text, 1, wxEXPAND);
  }
}

}  // namespace

// CHARTINSPECTOR_APPSTYLE_V3
void ChartInspectorPi::ApplyHoverWindowTheme() {
  if (!m_hoverInfoWindow) return;
  const ci_ui::AppPalette palette = ci_ui::AppStyle::PaletteFor(m_colorScheme);
  m_hoverInfoWindow->SetBackgroundColour(palette.windowBackground);
  m_hoverInfoWindow->SetForegroundColour(palette.textPrimary);
  if (m_hoverInfoTitle) {
    m_hoverInfoTitle->SetBackgroundColour(palette.windowBackground);
    m_hoverInfoTitle->SetForegroundColour(palette.textPrimary);
  }
  if (m_hoverInfoMeta) {
    m_hoverInfoMeta->SetBackgroundColour(palette.windowBackground);
    m_hoverInfoMeta->SetForegroundColour(palette.textPrimary);
  }
  if (m_hoverInfoBody) {
    m_hoverInfoBody->SetBackgroundColour(palette.windowBackground);
    m_hoverInfoBody->SetForegroundColour(palette.textSecondary);
  }
  if (m_hoverInfoDetails) {
    m_hoverInfoDetails->SetBackgroundColour(palette.cardBackground);
    m_hoverInfoDetails->SetForegroundColour(palette.textPrimary);
    if (auto *card = dynamic_cast<ci_ui::RoundedPanel *>(m_hoverInfoDetails))
      card->SetCardColours(palette.cardBackground, palette.cardBorder);
    const wxWindowList &children = m_hoverInfoDetails->GetChildren();
    for (wxWindowList::const_iterator it = children.begin(); it != children.end(); ++it) {
      if (auto *text = dynamic_cast<wxStaticText *>(*it)) {
        text->SetBackgroundColour(palette.cardBackground);
        text->SetForegroundColour(palette.textPrimary);
      }
    }
  }
  m_hoverInfoWindow->Refresh(false);
}

void ChartInspectorPi::HideHoverInfoPanel() {
  m_hoverInfoKey.clear();
  if (m_hoverInfoWindow) m_hoverInfoWindow->Hide();
}

void ChartInspectorPi::UpdateHoverInfoPanel(
    const wxString &feature, const wxString &objectName,
    const wxString &attributes, int geometryType,
    const wxString &associatedLightAttributes) {
  if (!m_enabled || feature.IsEmpty()) {
    HideHoverInfoPanel();
    return;
  }

  wxWindow *canvas = GetOCPNCanvasWindow();
  if (!canvas) return;

  if (!m_hoverInfoWindow) {
    m_hoverInfoWindow = new wxFrame(
        canvas, wxID_ANY, "Chart Inspector", wxDefaultPosition,
        wxSize(390, 230),
        wxCAPTION | wxCLOSE_BOX | wxRESIZE_BORDER | wxFRAME_TOOL_WINDOW |
            wxSTAY_ON_TOP);

    wxBoxSizer *root = new wxBoxSizer(wxVERTICAL);

    m_hoverInfoTitle =
        new wxStaticText(m_hoverInfoWindow, wxID_ANY, wxEmptyString);
    m_hoverInfoTitle->SetFont(
        ci_ui::AppStyle::TitleFont(m_hoverInfoTitle->GetFont()));
    root->Add(m_hoverInfoTitle, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP,
              ci_ui::AppStyle::kSpaceMd);

    m_hoverInfoMeta =
        new wxStaticText(m_hoverInfoWindow, wxID_ANY, wxEmptyString);
    m_hoverInfoMeta->SetFont(
        ci_ui::AppStyle::PrimaryFont(m_hoverInfoMeta->GetFont()));
    root->Add(m_hoverInfoMeta, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP,
              ci_ui::AppStyle::kSpaceSm);

    m_hoverInfoDetails =
        new ci_ui::RoundedPanel(m_hoverInfoWindow, ci_ui::AppStyle::kCardRadius);
    m_hoverInfoGrid = new wxFlexGridSizer(0, 2, 7, 18);
    m_hoverInfoGrid->AddGrowableCol(1, 1);
    wxBoxSizer *cardSizer = new wxBoxSizer(wxVERTICAL);
    cardSizer->Add(m_hoverInfoGrid, 1, wxEXPAND | wxALL,
                   ci_ui::AppStyle::kCardPadding);
    m_hoverInfoDetails->SetSizer(cardSizer);
    root->Add(m_hoverInfoDetails, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP,
              ci_ui::AppStyle::kSpaceMd);

    m_hoverInfoBody =
        new wxStaticText(m_hoverInfoWindow, wxID_ANY, wxEmptyString);
    m_hoverInfoBody->SetFont(
        ci_ui::AppStyle::TechnicalFont(m_hoverInfoBody->GetFont()));
    root->Add(m_hoverInfoBody, 0,
              wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM,
              ci_ui::AppStyle::kSpaceMd);
    root->SetItemMinSize(m_hoverInfoBody, -1, -1);

    m_hoverInfoWindow->SetSizer(root);
    m_hoverInfoWindow->SetMinSize(wxSize(330, 160));

    m_hoverInfoWindow->Bind(wxEVT_CLOSE_WINDOW, [this](wxCloseEvent &event) {
      if (m_hoverInfoWindow) m_hoverInfoWindow->Hide();
      m_hoverInfoKey.clear();
      event.Veto();
    });

    const wxPoint p = canvas->ClientToScreen(wxPoint(24, 80));
    m_hoverInfoWindow->Move(p);
    ApplyHoverWindowTheme();
  }

  wxString title = m_s57Catalog.ObjectName(feature);
  if (title.IsEmpty()) title = feature;
  m_hoverInfoTitle->SetLabel(CI_CleanDecodedCodes(title));

  const CI_NavigationInfo info = CI_BuildNavigationInfo(
      m_s57Catalog, feature, objectName, attributes, geometryType,
      m_showTechnicalData);

  m_hoverInfoMeta->SetLabel(info.primary);
  m_hoverInfoMeta->Show(!info.primary.IsEmpty());

  wxFlexGridSizer *grid = m_hoverInfoGrid;
  if (grid) {
    grid->Clear(true);
    const wxString colourRaw =
        m_s57Catalog.RawAttributeValue(attributes, "COLOUR");
    wxStringTokenizer lines(info.details, "\n", wxTOKEN_STRTOK);
    while (lines.HasMoreTokens()) {
      wxString line = lines.GetNextToken();
      line.Trim(true);
      line.Trim(false);
      if (line.IsEmpty()) continue;
      const int colon = line.Find(':');
      wxString label;
      wxString value;
      if (colon == wxNOT_FOUND) {
        label = "Info";
        value = line;
      } else {
        label = line.Left(colon);
        value = line.Mid(colon + 1);
        label.Trim(true);
        label.Trim(false);
        value.Trim(true);
        value.Trim(false);
      }
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
    ApplyHoverWindowTheme();
  }

  if (m_showTechnicalData && !info.technical.IsEmpty()) {
    m_hoverInfoBody->SetLabel("Technical\n" + info.technical);
    m_hoverInfoBody->Show();
  } else {
    m_hoverInfoBody->SetLabel(wxEmptyString);
    m_hoverInfoBody->Hide();
  }

  m_hoverInfoWindow->Layout();
  m_hoverInfoWindow->Fit();
  wxSize size = m_hoverInfoWindow->GetSize();
  size.SetWidth(std::max(350, std::min(500, size.GetWidth())));
  size.SetHeight(std::max(155, std::min(560, size.GetHeight())));
  m_hoverInfoWindow->SetSize(size);
  m_hoverInfoWindow->Layout();

  if (!m_hoverInfoWindow->IsShown()) m_hoverInfoWindow->Show();
}

void ChartInspectorPi::ClearHoverGeometry() {
  m_hoverPoints.clear(); m_hoverParts.clear(); m_hoverFeature.clear();
  m_hoverGeometryType = 0; m_hasHoverGeometry = false;
  HideHoverInfoPanel();
}

void ChartInspectorPi::ClearHover() {
  ClearHoverGeometry();
  m_hasVectorObject = false;
  m_lastFeature.clear();
  m_lastObjectName.clear();
  m_lastAttributes.clear();
  m_associatedLightAttributes.clear();
  m_hasAssociatedLight = false;
  m_lastPrimitiveType = 1;
}

bool ChartInspectorPi::IsFeatureEnabled(const wxString &feature) const {
  const wxString candidate = feature.Upper();
  wxStringTokenizer tokens(m_featureFilter, ",; \t\r\n", wxTOKEN_STRTOK);
  while (tokens.HasMoreTokens()) {
    wxString token = tokens.GetNextToken().Upper();
    token.Trim(true);
    token.Trim(false);
    if (token.EndsWith("*")) {
      token.RemoveLast();
      if (!token.IsEmpty() && candidate.StartsWith(token)) return true;
    } else if (candidate == token) {
      return true;
    }
  }
  return false;
}

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

wxString ChartInspectorPi::BuildLightSummary(const wxString &attributes) const {
  const wxString chr = m_s57Catalog.RawAttributeValue(attributes, "LITCHR");
  const wxString grp = m_s57Catalog.RawAttributeValue(attributes, "SIGGRP");
  const wxString col = m_s57Catalog.RawAttributeValue(attributes, "COLOUR");
  const wxString per = m_s57Catalog.RawAttributeValue(attributes, "SIGPER");
  long c = 0;
  chr.ToLong(&c);
  wxString abbr;
  switch (c) {
    case 1: abbr = "F"; break;
    case 2: abbr = "Fl"; break;
    case 3: abbr = "LFl"; break;
    case 4: abbr = "Q"; break;
    case 5: abbr = "VQ"; break;
    case 6: abbr = "UQ"; break;
    case 7: abbr = "Iso"; break;
    case 8: abbr = "Oc"; break;
    case 9: abbr = "IQ"; break;
    case 10: abbr = "IVQ"; break;
    case 11: abbr = "IUQ"; break;
    case 12: abbr = "Mo"; break;
    case 13: abbr = "F.Fl"; break;
    case 14: abbr = "Fl.LFl"; break;
    case 28: abbr = "Al"; break;
    case 29: abbr = "F.Al.Fl"; break;
    default: abbr = m_s57Catalog.DecodeValue("LITCHR", chr); break;
  }
  if (!grp.IsEmpty() && grp != "()" && grp != "(1)") abbr += grp;
  long colourCode = 0;
  col.BeforeFirst(',').ToLong(&colourCode);
  wxString colourAbbr;
  switch (colourCode) {
    case 1: colourAbbr = "W"; break;
    case 3: colourAbbr = "R"; break;
    case 4: colourAbbr = "G"; break;
    case 5: colourAbbr = "Bu"; break;
    case 6: colourAbbr = "Y"; break;
    default: colourAbbr = m_s57Catalog.DecodeValue("COLOUR", col); break;
  }
  wxString result = abbr;
  if (!colourAbbr.IsEmpty()) result += " " + colourAbbr;
  if (!per.IsEmpty()) result += " " + per + "s";
  return result.IsEmpty() ? "Light" : result;
}

void ChartInspectorPi::StopLightPreview() {
  if (m_lightTimer) {
    m_lightTimer->Stop();
    delete m_lightTimer;
    m_lightTimer = nullptr;
  }
  m_lightIndicator = nullptr;
}

void ChartInspectorPi::UpdateLightIndicator() {
  if (!m_lightIndicator) return;
  bool on = true;
  if (!m_lightIsFixed && m_lightPeriodSeconds > 0.05) {
    const long long periodMs =
        static_cast<long long>(m_lightPeriodSeconds * 1000.0);
    const long long phaseMs = wxGetUTCTimeMillis().GetValue() % periodMs;
    const double phase = static_cast<double>(phaseMs) / periodMs;
    if (m_lightCharacteristic == 7) {
      on = phase < 0.5;  // Iso: equal light and dark intervals.
    } else if (m_lightCharacteristic == 8) {
      on = phase < 0.75;  // Oc: light longer than eclipse, schematic preview.
    } else if (m_lightCharacteristic == 4 || m_lightCharacteristic == 5 ||
               m_lightCharacteristic == 6) {
      if (m_lightGroupCount <= 1) {
        on = phase < 0.25;
      } else {
        const double activeWindow = m_lightHasLongFlash ? 0.72 : 0.62;
        if (m_lightHasLongFlash && phase > 0.74 && phase < 0.90) {
          on = true;
        } else if (phase < activeWindow) {
          const double local =
              std::fmod(phase * m_lightGroupCount / activeWindow, 1.0);
          on = local < 0.24;
        } else {
          on = false;
        }
      }
    } else {
      const int flashes = std::max(1, m_lightGroupCount);
      const double activeWindow = 0.62;
      if (phase < activeWindow) {
        const double local = std::fmod(phase * flashes / activeWindow, 1.0);
        on = local < 0.22;
      } else {
        on = false;
      }
    }
  }
  m_lightOn = on;
  m_lightIndicator->Refresh(false);
}

void ChartInspectorPi::BuildVisualSummary() {
  if (!m_infoVisual) return;
  StopLightPreview();
  wxSizer *sizer = m_infoVisual->GetSizer();
  if (!sizer) {
    sizer = new wxBoxSizer(wxVERTICAL);
    m_infoVisual->SetSizer(sizer);
  }
  sizer->Clear(true);

  if (m_lastFeature != "LIGHTS") {
    const wxString colourRaw =
        m_s57Catalog.RawAttributeValue(m_lastAttributes, "COLOUR");
    if (!colourRaw.IsEmpty()) {
      wxBoxSizer *row = new wxBoxSizer(wxHORIZONTAL);
      wxStaticText *label = new wxStaticText(m_infoVisual, wxID_ANY, "Colour");
      wxFont f = label->GetFont();
      f.SetWeight(wxFONTWEIGHT_BOLD);
      label->SetFont(f);
      row->Add(label, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 10);
      wxStringTokenizer values(colourRaw, ",", wxTOKEN_STRTOK);
      while (values.HasMoreTokens()) {
        wxString token = values.GetNextToken();
        token.Trim(true);
        token.Trim(false);
        wxPanel *chip = new wxPanel(m_infoVisual, wxID_ANY, wxDefaultPosition,
                                    wxSize(18, 18), wxBORDER_SIMPLE);
        chip->SetMinSize(wxSize(18, 18));
        chip->SetBackgroundColour(SignalColour(token));
        row->Add(chip, 0, wxALIGN_CENTER_VERTICAL | wxRIGHT, 5);
      }
      row->Add(new wxStaticText(
                   m_infoVisual, wxID_ANY,
                   m_s57Catalog.DecodeValue("COLOUR", colourRaw)),
               0, wxALIGN_CENTER_VERTICAL);
      sizer->Add(row, 0, wxBOTTOM, 10);
    }
  }

  wxString lightAttributes;
  if (m_lastFeature == "LIGHTS")
    lightAttributes = m_lastAttributes;
  else if (m_hasAssociatedLight)
    lightAttributes = m_associatedLightAttributes;

  if (!lightAttributes.IsEmpty()) {
    const wxString lightColourRaw =
        m_s57Catalog.RawAttributeValue(lightAttributes, "COLOUR");
    wxBoxSizer *lightRow = new wxBoxSizer(wxHORIZONTAL);
    m_lightColour = SignalColour(lightColourRaw);
    m_lightIndicator = new wxPanel(m_infoVisual, wxID_ANY, wxDefaultPosition,
                                   wxSize(30, 30), wxBORDER_NONE);
    m_lightIndicator->SetMinSize(wxSize(30, 30));
    m_lightIndicator->SetBackgroundStyle(wxBG_STYLE_PAINT);
    m_lightIndicator->Bind(wxEVT_PAINT, [this](wxPaintEvent &) {
      if (!m_lightIndicator) return;
      wxAutoBufferedPaintDC dc(m_lightIndicator);
      wxColour background = m_infoVisual->GetBackgroundColour();
      wxColour border = wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOWTEXT);
      GetGlobalColor("DILG4", &border);
      wxColour offColour(68, 68, 68);
      if (m_colorScheme == PI_GLOBAL_COLOR_SCHEME_DUSK)
        offColour = wxColour(58, 58, 58);
      else if (m_colorScheme == PI_GLOBAL_COLOR_SCHEME_NIGHT)
        offColour = wxColour(44, 44, 44);
      dc.SetBackground(wxBrush(background));
      dc.Clear();
      dc.SetPen(wxPen(border, 2));
      dc.SetBrush(wxBrush(m_lightOn ? m_lightColour : offColour));
      dc.DrawRectangle(5, 5, 20, 20);
    });
    lightRow->Add(m_lightIndicator, 0, wxALIGN_TOP | wxRIGHT, 10);

    wxBoxSizer *lightText = new wxBoxSizer(wxVERTICAL);
    wxStaticText *character = new wxStaticText(
        m_infoVisual, wxID_ANY,
        (m_lastFeature == "LIGHTS" ? wxString() : "Light  ") +
            BuildLightSummary(lightAttributes));
    wxFont cf = character->GetFont();
    cf.SetWeight(wxFONTWEIGHT_BOLD);
    cf.SetPointSize(cf.GetPointSize() + 2);
    character->SetFont(cf);
    lightText->Add(character, 0);

    wxString lightDetails;
    const wxString height =
        m_s57Catalog.RawAttributeValue(lightAttributes, "HEIGHT");
    const wxString range =
        m_s57Catalog.RawAttributeValue(lightAttributes, "VALNMR");
    const wxString visibility =
        m_s57Catalog.RawAttributeValue(lightAttributes, "LITVIS");
    const wxString sector1 =
        m_s57Catalog.RawAttributeValue(lightAttributes, "SECTR1");
    const wxString sector2 =
        m_s57Catalog.RawAttributeValue(lightAttributes, "SECTR2");
    AppendInfoLine(&lightDetails, "Light height", MetresAndFeet(height));
    if (!range.IsEmpty()) AppendInfoLine(&lightDetails, "Nominal range", range + " NM");
    if (!visibility.IsEmpty())
      AppendInfoLine(&lightDetails, "Visibility",
                     m_s57Catalog.DecodeValue("LITVIS", visibility));
    if (!sector1.IsEmpty() || !sector2.IsEmpty()) {
      wxString sector;
      if (!sector1.IsEmpty()) sector += sector1 + wxString::FromUTF8("°");
      if (!sector1.IsEmpty() && !sector2.IsEmpty()) sector += " - ";
      if (!sector2.IsEmpty()) sector += sector2 + wxString::FromUTF8("°");
      AppendInfoLine(&lightDetails, "Sector", sector);
    }
    if (!lightDetails.IsEmpty()) {
      wxStaticText *details =
          new wxStaticText(m_infoVisual, wxID_ANY, lightDetails);
      lightText->Add(details, 0, wxTOP, 4);
    }

    const wxString groupRaw =
        m_s57Catalog.RawAttributeValue(lightAttributes, "SIGGRP");
    const bool complexPattern =
        (!groupRaw.IsEmpty() && groupRaw != "()" && groupRaw != "(1)") ||
        m_s57Catalog.RawAttributeValue(lightAttributes, "SIGSEQ").length() > 0;
    wxStaticText *note = new wxStaticText(
        m_infoVisual, wxID_ANY,
        complexPattern
            ? "Schematic animated preview; encoded light characteristic is authoritative"
            : "Animated preview of the encoded light characteristic");
    wxFont nf = note->GetFont();
    nf.SetPointSize(std::max(7, nf.GetPointSize() - 1));
    note->SetFont(nf);
    lightText->Add(note, 0, wxTOP, 4);
    lightRow->Add(lightText, 1, wxEXPAND);
    sizer->Add(lightRow, 0, wxEXPAND | wxBOTTOM, 10);

    long chr = 0;
    m_s57Catalog.RawAttributeValue(lightAttributes, "LITCHR").ToLong(&chr);
    m_lightCharacteristic = static_cast<int>(chr);
    m_lightIsFixed = chr == 1;
    m_lightPeriodSeconds = 0.0;
    const bool hasEncodedPeriod =
        m_s57Catalog.RawAttributeValue(lightAttributes, "SIGPER")
            .ToDouble(&m_lightPeriodSeconds);

    m_lightGroupCount = 1;
    wxString group = groupRaw;
    m_lightHasLongFlash = group.Upper().Find("LFL") != wxNOT_FOUND;
    wxString countPart = group;
    const int plus = countPart.Find('+');
    if (plus != wxNOT_FOUND) countPart = countPart.Left(plus);
    countPart.Replace("(", "");
    countPart.Replace(")", "");
    long groupCount = 1;
    if (countPart.ToLong(&groupCount) && groupCount > 0)
      m_lightGroupCount = static_cast<int>(groupCount);

    if (!hasEncodedPeriod || m_lightPeriodSeconds <= 0.05) {
      if (m_lightGroupCount <= 1) {
        if (chr == 4)
          m_lightPeriodSeconds = 1.0;
        else if (chr == 5)
          m_lightPeriodSeconds = 0.5;
        else if (chr == 6)
          m_lightPeriodSeconds = 0.25;
      } else {
        m_lightPeriodSeconds = 0.0;
      }
    }

    m_lightOn = m_lightIsFixed;
    UpdateLightIndicator();
    if (!m_lightIsFixed && m_lightPeriodSeconds > 0.05) {
      m_lightTimer = new wxTimer();
      m_lightTimer->SetOwner(m_infoPanel);
      m_infoPanel->Bind(wxEVT_TIMER,
                        [this](wxTimerEvent &) { UpdateLightIndicator(); },
                        m_lightTimer->GetId());
      m_lightTimer->Start(50);
    }
  }

  m_infoVisual->Show(sizer->GetItemCount() > 0);
  m_infoVisual->Layout();
  ApplyInfoTheme();
}

void ChartInspectorPi::BuildInfoPanel(wxWindow *canvas) {
  if (m_infoPanel || !canvas) return;
  m_infoPanel = new wxPanel(canvas, wxID_ANY, wxDefaultPosition, wxDefaultSize,
                            wxBORDER_SIMPLE);
  wxBoxSizer *root = new wxBoxSizer(wxVERTICAL);
  wxBoxSizer *header = new wxBoxSizer(wxHORIZONTAL);
  m_infoTitle = new wxStaticText(m_infoPanel, wxID_ANY, wxEmptyString);
  wxFont titleFont = m_infoTitle->GetFont();
  titleFont.SetWeight(wxFONTWEIGHT_BOLD);
  titleFont.SetPointSize(titleFont.GetPointSize() + 2);
  m_infoTitle->SetFont(titleFont);
  header->Add(m_infoTitle, 1, wxALIGN_CENTER_VERTICAL);
  wxButton *close = new wxButton(m_infoPanel, wxID_ANY, "x", wxDefaultPosition,
                                 wxSize(28, 26), wxBU_EXACTFIT);
  close->Bind(wxEVT_BUTTON, [this](wxCommandEvent &) { HideObjectPopup(); });
  header->Add(close, 0, wxLEFT, 8);
  root->Add(header, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP, 12);
  m_infoSubtitle = new wxStaticText(m_infoPanel, wxID_ANY, wxEmptyString);
  root->Add(m_infoSubtitle, 0, wxLEFT | wxRIGHT | wxTOP, 8);
  m_infoAcronym = new wxStaticText(m_infoPanel, wxID_ANY, wxEmptyString);
  root->Add(m_infoAcronym, 0, wxLEFT | wxRIGHT | wxTOP, 8);
  root->Add(new wxStaticLine(m_infoPanel), 0,
            wxEXPAND | wxLEFT | wxRIGHT | wxTOP | wxBOTTOM, 12);
  m_infoVisual = new wxPanel(m_infoPanel, wxID_ANY);
  m_infoVisual->SetSizer(new wxBoxSizer(wxVERTICAL));
  root->Add(m_infoVisual, 0, wxEXPAND | wxLEFT | wxRIGHT, 12);
  m_infoBody = new wxStaticText(m_infoPanel, wxID_ANY, wxEmptyString);
  root->Add(m_infoBody, 0, wxEXPAND | wxLEFT | wxRIGHT | wxTOP, 12);
  m_infoTechnical = new wxStaticText(m_infoPanel, wxID_ANY, wxEmptyString);
  wxFont techFont = m_infoTechnical->GetFont();
  techFont.SetPointSize(std::max(7, techFont.GetPointSize() - 1));
  m_infoTechnical->SetFont(techFont);
  root->Add(m_infoTechnical, 0, wxEXPAND | wxALL, 12);
  m_infoPanel->SetSizer(root);
  ApplyInfoTheme();
  m_infoPanel->Hide();
}

void ChartInspectorPi::HideObjectPopup() {
  StopLightPreview();
  if (m_infoPanel) m_infoPanel->Hide();
}

void ChartInspectorPi::ShowObjectPopup() {
  if (!m_enabled || !m_hasVectorObject || m_lastFeature.IsEmpty()) return;
  wxWindow *canvas = GetOCPNCanvasWindow();
  if (!canvas) return;
  BuildInfoPanel(canvas);
  m_infoTitle->SetLabel(m_s57Catalog.ObjectName(m_lastFeature));
  m_infoSubtitle->SetLabel(m_lastObjectName);
  m_infoSubtitle->Show(!m_lastObjectName.IsEmpty());
  const wxString geometry = m_lastPrimitiveType == 3 ? "Area" :
                            m_lastPrimitiveType == 2 ? "Line" : "Point";
  m_infoAcronym->SetLabel("S-57: " + m_lastFeature + "  -  " + geometry);
  BuildVisualSummary();

  wxString bodyAttributes = m_lastAttributes;
  if (m_lastFeature == "LIGHTS") {
    bodyAttributes = FilterRawAttributes(
        bodyAttributes,
        {"COLOUR", "LITCHR", "SIGGRP", "SIGPER", "SIGSEQ", "HEIGHT",
         "VALNMR", "LITVIS", "SECTR1", "SECTR2"});
  }
  wxString technical;
  const wxString readable =
      m_s57Catalog.FormatAttributes(bodyAttributes, &technical);
  m_infoBody->SetLabel(readable);
  m_infoBody->Wrap(360);
  m_infoBody->Show(!readable.IsEmpty());

  if (m_showTechnicalData) {
    wxString raw = "Technical S-57 data\n" + m_lastFeature;
    wxString allTechnical;
    m_s57Catalog.FormatAttributes(m_lastAttributes, &allTechnical);
    if (!allTechnical.IsEmpty()) raw += "\n" + allTechnical;
    if (m_hasAssociatedLight) {
      wxString lightTechnical;
      m_s57Catalog.FormatAttributes(m_associatedLightAttributes,
                                    &lightTechnical);
      raw += "\n\nAssociated LIGHTS";
      if (!lightTechnical.IsEmpty()) raw += "\n" + lightTechnical;
    }
    m_infoTechnical->SetLabel(raw);
    m_infoTechnical->Wrap(360);
    m_infoTechnical->Show();
  } else {
    m_infoTechnical->Hide();
  }

  ApplyInfoTheme();
  m_infoPanel->Layout();
  m_infoPanel->Fit();
  wxSize size = m_infoPanel->GetSize();
  size.SetWidth(std::max(340, std::min(460, size.GetWidth())));
  m_infoPanel->SetSize(size);
  m_infoPanel->Layout();
  const wxSize canvasSize = canvas->GetClientSize();
  m_infoPanel->Move(std::max(12, canvasSize.GetWidth() - size.GetWidth() - 14),
                    14);
  m_infoPanel->Show();
  m_infoPanel->Raise();
}

void ChartInspectorPi::QueryAssociatedLight() {
  m_associatedLightAttributes.clear();
  m_hasAssociatedLight = false;
  if (!(m_lastFeature.StartsWith("BOY") || m_lastFeature.StartsWith("BCN")))
    return;
  HitTestV3Fn query = m_hitTestV4 ? m_hitTestV4 : m_hitTestV3;
  if (!query) return;
  char feature[32] = {0};
  char objectName[128] = {0};
  char attributes[2048] = {0};
  int primitiveType = 1;
  double markerLat = 0.0;
  double markerLon = 0.0;
  const bool found = query(
      0, m_lastObjectLat, m_lastObjectLon,
      static_cast<double>(std::max(8, m_hitRadiusPixels)), "LIGHTS", feature,
      static_cast<int>(sizeof(feature)), objectName,
      static_cast<int>(sizeof(objectName)), attributes,
      static_cast<int>(sizeof(attributes)), &primitiveType, &markerLat,
      &markerLon);
  if (found && wxString::FromUTF8(feature).Upper() == "LIGHTS") {
    m_associatedLightAttributes = wxString::FromUTF8(attributes);
    m_hasAssociatedLight = !m_associatedLightAttributes.IsEmpty();
  }
}

void ChartInspectorPi::UpdateHoverObject() {
  if (!m_enabled ||
      (!m_hitTestV4 && !m_hitTestV3 && !m_hitTestV2 && !m_hitTest) ||
      !m_hasCursorPosition) {
    ClearHover();
    return;
  }
  char feature[32] = {0};
  char objectName[128] = {0};
  char attributes[2048] = {0};
  double markerLat = 0.0;
  double markerLon = 0.0;
  int primitiveType = 1;
  bool found = false;
  const wxCharBuffer filter = m_featureFilter.ToUTF8();
  if (m_hitTestV4 || m_hitTestV3) {
    HitTestV3Fn query = m_hitTestV4 ? m_hitTestV4 : m_hitTestV3;
    found = query(0, m_cursorLat, m_cursorLon,
                  static_cast<double>(m_hitRadiusPixels), filter.data(), feature,
                  static_cast<int>(sizeof(feature)), objectName,
                  static_cast<int>(sizeof(objectName)), attributes,
                  static_cast<int>(sizeof(attributes)), &primitiveType,
                  &markerLat, &markerLon);
  } else if (m_hitTestV2) {
    found = m_hitTestV2(0, m_cursorLat, m_cursorLon,
                        static_cast<double>(m_hitRadiusPixels), feature,
                        static_cast<int>(sizeof(feature)), objectName,
                        static_cast<int>(sizeof(objectName)), attributes,
                        static_cast<int>(sizeof(attributes)), &markerLat,
                        &markerLon);
  } else if (m_hitTest) {
    found = m_hitTest(0, m_cursorLat, m_cursorLon,
                      static_cast<double>(m_hitRadiusPixels), feature,
                      static_cast<int>(sizeof(feature)), objectName,
                      static_cast<int>(sizeof(objectName)), &markerLat,
                      &markerLon);
  }
  const wxString featureName = wxString::FromUTF8(feature).Upper();
  if (found && !IsFeatureEnabled(featureName)) found = false;
  if (!found) {
    ClearHover();
    return;
  }
  m_hasVectorObject = true;
  m_lastFeature = featureName;
  m_lastObjectName = wxString::FromUTF8(objectName);
  m_lastAttributes = wxString::FromUTF8(attributes);
  m_lastObjectLat = markerLat;
  m_lastObjectLon = markerLon;
  m_lastPrimitiveType = primitiveType;
  QueryAssociatedLight();
}

void ChartInspectorPi::UpdateHoverGeometry(bool force) {
#ifdef _WIN32
  if (!m_enabled || !m_hasCursorPosition || !m_hasMousePosition) { ClearHoverGeometry(); return; }
  const long long now = wxGetUTCTimeMillis().GetValue();
  const int dx = m_mousePosition.x - m_lastHoverQueryPosition.x;
  const int dy = m_mousePosition.y - m_lastHoverQueryPosition.y;
  if (!force && now - m_lastHoverQueryMs < 75) return;
  if (!force && m_lastHoverQueryMs && dx * dx + dy * dy < 9) return;
  HMODULE host = GetModuleHandleW(nullptr);
  auto queryFn = host ? reinterpret_cast<CI_QueryVectorV1>(GetProcAddress(host, "QueryVectorChartObjectsV1")) : nullptr;
  if (!queryFn) { ClearHoverGeometry(); return; }
  CI_VectorQueryV1 q{};
  q.struct_size = sizeof(q); q.lat = m_cursorLat; q.lon = m_cursorLon;
  q.search_radius_pixels = static_cast<double>(std::max(8, m_hitRadiusPixels));
  q.flags = CI_SKIP_ATTRIBUTES; q.geometry_mask = CI_GEOMETRY_ALL;
  // CHARTINSPECTOR_FULL_HIGHLIGHT_GEOMETRY_V1
  q.max_objects = 8; q.max_points_per_object = 512;
  q.exclude_feature_classes_utf8 = "LNDARE,COALNE,DEPARE,DEPCNT,M_NPUB,M_COVR,M_NSYS,MAGVAR,SEAARE";
  CI_HoverCandidate best;
  best.cursorLat = m_cursorLat;
  best.cursorLon = m_cursorLon;
  best.includeFilter = m_featureFilter;
  bool usedHiddenFallback = false;

  // Pass 1: only objects which the active chart currently renders.
  queryFn(0, &q, CI_CollectHover, &best);

  // Pass 2: if the visible pass is empty, look for useful navigation objects
  // which are hidden by portrayal or live in a more detailed cached ENC cell.
  // The dedicated sink deliberately rejects generic hidden lines/areas.
  if (m_includeScaleHidden && best.points.empty()) {
    CI_HoverCandidate hidden;
    hidden.cursorLat = m_cursorLat;
    hidden.cursorLon = m_cursorLon;
    hidden.includeFilter = m_featureFilter;
    q.flags = CI_SKIP_ATTRIBUTES | CI_INCLUDE_NON_RENDERED |
              CI_PREFER_DETAILED_CHART;
    queryFn(0, &q, CI_CollectHover, &hidden);
    if (!hidden.points.empty()) {
      best = hidden;
      usedHiddenFallback = true;
    }
  }

  if (!best.points.empty()) {
    const wxString key =
        best.feature + "|" + wxString::Format("%u|%.8f|%.8f", best.geometry,
                                               best.points[0].lat,
                                               best.points[0].lon);
    if (key == m_hoverInfoKey && m_hasHoverGeometry &&
        m_hoverFeature == best.feature) {
      m_lastHoverQueryMs = now;
      m_lastHoverQueryPosition = m_mousePosition;
      return;
    }

    if (key != m_hoverInfoKey) {
      CI_HoverCandidate details;
      details.cursorLat = m_cursorLat;
      details.cursorLon = m_cursorLon;
      details.includeFilter = m_featureFilter;
      q.flags &= ~CI_SKIP_ATTRIBUTES;
      q.max_points_per_object = 16384;
      queryFn(0, &q, CI_CollectHover, &details);
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
          // CHARTINSPECTOR_ASSOC_LIGHT_QUERY_TYPE_FIX_V2
          auto lightQuery = q;
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
      } else {
        HideHoverInfoPanel();
      }
    }
  }

  m_lastHoverQueryMs = now; m_lastHoverQueryPosition = m_mousePosition;
  if (best.points.empty()) { ClearHoverGeometry(); return; }
  m_hoverPoints.clear();
  m_hoverParts.clear();
  for (const auto &p : best.points) m_hoverPoints.push_back({p.lat, p.lon});
  for (const auto &part : best.parts) m_hoverParts.push_back({part.firstPoint, part.pointCount});
  m_hoverGeometryType = static_cast<int>(best.geometry); m_hoverFeature = best.feature;
  m_hasHoverGeometry = true;
#else
  (void)force;
#endif
}

bool ChartInspectorPi::MouseEventHook(wxMouseEvent &event) {
  m_mousePosition = event.GetPosition();
  m_hasMousePosition = true;
  UpdateHoverGeometry(event.LeftDown());
  if (event.LeftDown()) UpdateHoverObject();
  if (event.LeftDown()) {
    if (m_hasVectorObject)
      ShowObjectPopup();
    else
      HideObjectPopup();
  }
  wxWindow *canvas = GetOCPNCanvasWindow();
  if (canvas) RequestRefresh(canvas);
  return false;
}

void ChartInspectorPi::OnToolbarToolCallback(int id) {
  if (id != m_toolbarId) return;
  m_enabled = !m_enabled;
  UpdateToolbarVisual();
  if (!m_enabled) {
    ClearHover();
    HideObjectPopup();
  }
  SaveConfig();
  wxWindow *canvas = GetOCPNCanvasWindow();
  if (canvas) RequestRefresh(canvas);
}

void ChartInspectorPi::ShowPreferencesDialog(wxWindow *parent) {
  HideObjectPopup();
  wxDialog dialog(parent, wxID_ANY, "Chart Inspector Preferences",
                  wxDefaultPosition, wxSize(650, 650),
                  wxDEFAULT_DIALOG_STYLE | wxRESIZE_BORDER);
  wxBoxSizer *root = new wxBoxSizer(wxVERTICAL);
  wxCheckBox *enabled =
      new wxCheckBox(&dialog, wxID_ANY, "Enable Chart Inspector");
  enabled->SetValue(m_enabled);
  root->Add(enabled, 0, wxALL, 10);

  wxBoxSizer *radiusRow = new wxBoxSizer(wxHORIZONTAL);
  radiusRow->Add(new wxStaticText(&dialog, wxID_ANY, "Hit radius:"), 0,
                 wxALIGN_CENTER_VERTICAL | wxRIGHT, 8);
  wxSpinCtrl *radius = new wxSpinCtrl(&dialog, wxID_ANY);
  radius->SetRange(2, 20);
  radius->SetValue(m_hitRadiusPixels);
  radiusRow->Add(radius, 0);
  radiusRow->Add(new wxStaticText(&dialog, wxID_ANY, "pixels"), 0,
                 wxALIGN_CENTER_VERTICAL | wxLEFT, 6);
  root->Add(radiusRow, 0, wxLEFT | wxRIGHT | wxBOTTOM, 10);

  wxCheckListBox *classes = new wxCheckListBox(
      &dialog, wxID_ANY, wxDefaultPosition, wxSize(580, 400));
  std::vector<wxString> classAcronyms;
  for (const auto &info : m_s57Catalog.ObjectClasses()) {
    const unsigned int index = classes->Append(info.acronym + "  -  " + info.name);
    classes->Check(index, IsFeatureEnabled(info.acronym));
    classAcronyms.push_back(info.acronym);
  }
  root->Add(classes, 1, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, 10);

  wxCheckBox *scaleHidden = new wxCheckBox(
      &dialog, wxID_ANY,
      "Also inspect selected objects hidden only by chart scale (SCAMIN)");
  scaleHidden->SetValue(m_includeScaleHidden);
  root->Add(scaleHidden, 0, wxLEFT | wxRIGHT | wxBOTTOM, 10);

  wxCheckBox *technical = new wxCheckBox(
      &dialog, wxID_ANY,
      "Show technical S-57 metadata (class, geometry, SCAMIN and source data)");
  technical->SetValue(m_showTechnicalData);
  root->Add(technical, 0, wxLEFT | wxRIGHT | wxBOTTOM, 10);
  root->Add(dialog.CreateSeparatedButtonSizer(wxOK | wxCANCEL), 0,
            wxEXPAND | wxALL, 10);
  dialog.SetSizer(root);
  DimeWindow(&dialog);
  dialog.CentreOnParent();

  if (dialog.ShowModal() == wxID_OK) {
    m_enabled = enabled->GetValue();
    m_hitRadiusPixels = radius->GetValue();
    m_showTechnicalData = technical->GetValue();
    m_includeScaleHidden = scaleHidden->GetValue();
    wxString filterValue;
    for (unsigned int i = 0; i < classes->GetCount(); ++i) {
      if (!classes->IsChecked(i)) continue;
      if (!filterValue.IsEmpty()) filterValue += ",";
      filterValue += classAcronyms[i];
    }
    m_featureFilter = filterValue;
    UpdateToolbarVisual();
    if (!m_enabled) ClearHover();
    SaveConfig();
    wxWindow *canvas = GetOCPNCanvasWindow();
    if (canvas) RequestRefresh(canvas);
  }
}

void ChartInspectorPi::SendVectorChartObjectInfo(
    wxString &chart, wxString &feature, wxString &objname, double lat,
    double lon, double scale, int nativescale) {
  (void)chart;
  (void)feature;
  (void)objname;
  (void)lat;
  (void)lon;
  (void)scale;
  (void)nativescale;
}

bool ChartInspectorPi::RenderOverlay(wxDC &dc, PlugIn_ViewPort *vp) {
  if (!vp || !m_enabled) return false;
  if (m_hasHoverGeometry) {
    dc.SetBrush(*wxTRANSPARENT_BRUSH);
    auto draw = [&](int width, const wxColour &colour) {
      dc.SetPen(wxPen(colour, width));
      if (m_hoverGeometryType == 1 && !m_hoverPoints.empty()) {
        wxPoint p; GetCanvasPixLL(vp, &p, m_hoverPoints[0].lat, m_hoverPoints[0].lon);
        dc.DrawCircle(p, width > 5 ? 15 : 12);
      } else {
        for (const auto &part : m_hoverParts) {
          if (part.pointCount < 2 || part.firstPoint >= m_hoverPoints.size()) continue;
          std::vector<wxPoint> pix;
          const unsigned int end = std::min<unsigned int>(part.firstPoint + part.pointCount, static_cast<unsigned int>(m_hoverPoints.size()));
          for (unsigned int i = part.firstPoint; i < end; ++i) {
            wxPoint p; GetCanvasPixLL(vp, &p, m_hoverPoints[i].lat, m_hoverPoints[i].lon); pix.push_back(p);
          }
          if (pix.size() >= 2) dc.DrawLines(static_cast<int>(pix.size()), pix.data());
        }
      }
    };
    draw(9, wxColour(0, 120, 160)); draw(3, wxColour(0, 255, 255));
    return true;
  }
  if (!m_hasVectorObject) return false;
  wxPoint p; GetCanvasPixLL(vp, &p, m_lastObjectLat, m_lastObjectLon);
  dc.SetBrush(*wxTRANSPARENT_BRUSH); dc.SetPen(wxPen(wxColour(0, 255, 255), 3)); dc.DrawCircle(p, 12);
  return true;
}

bool ChartInspectorPi::RenderGLOverlayMultiCanvas(wxGLContext *pcontext,
                                                   PlugIn_ViewPort *vp,
                                                   int canvasIndex,
                                                   int priority) {
  (void)pcontext;
  (void)canvasIndex;
  if (!vp) return false;
  if (priority != -1 && priority != OVERLAY_LEGACY) return false;
  if (!m_enabled || (!m_hasVectorObject && !m_hasHoverGeometry)) return true;
  glPushAttrib(GL_ENABLE_BIT | GL_COLOR_BUFFER_BIT | GL_LINE_BIT |
               GL_TRANSFORM_BIT | GL_VIEWPORT_BIT | GL_CURRENT_BIT);
  glDisable(GL_TEXTURE_2D);
  glDisable(GL_DEPTH_TEST);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glMatrixMode(GL_PROJECTION);
  glPushMatrix();
  glLoadIdentity();
  glOrtho(0.0, static_cast<double>(vp->pix_width),
          static_cast<double>(vp->pix_height), 0.0, -1.0, 1.0);
  glMatrixMode(GL_MODELVIEW);
  glPushMatrix();
  glLoadIdentity();
  auto drawHoverGL = [&](float width, float alpha) {
    glLineWidth(width); glColor4f(0.0f, 1.0f, 1.0f, alpha);
    if (m_hasHoverGeometry && m_hoverGeometryType == 1 && !m_hoverPoints.empty()) {
      wxPoint p; GetCanvasPixLL(vp, &p, m_hoverPoints[0].lat, m_hoverPoints[0].lon);
      const float r = width > 5.0f ? 15.0f : 12.0f; glBegin(GL_LINE_LOOP);
      for (int i = 0; i < 32; ++i) { const float a = i * 6.28318530718f / 32.0f; glVertex2f(p.x + r*cosf(a), p.y + r*sinf(a)); }
      glEnd();
    } else if (m_hasHoverGeometry) {
      for (const auto &part : m_hoverParts) {
        if (part.pointCount < 2 || part.firstPoint >= m_hoverPoints.size()) continue;
        const unsigned int end = std::min<unsigned int>(part.firstPoint + part.pointCount, static_cast<unsigned int>(m_hoverPoints.size()));
        glBegin(GL_LINE_STRIP);
        for (unsigned int i = part.firstPoint; i < end; ++i) { wxPoint p; GetCanvasPixLL(vp, &p, m_hoverPoints[i].lat, m_hoverPoints[i].lon); glVertex2f((float)p.x, (float)p.y); }
        glEnd();
      }
    }
  };
  if (m_hasHoverGeometry) { drawHoverGL(9.0f, 0.32f); drawHoverGL(3.0f, 0.95f); }
  else {
    wxPoint p; GetCanvasPixLL(vp, &p, m_lastObjectLat, m_lastObjectLon);
    glColor4f(0.0f, 1.0f, 1.0f, 0.9f); glLineWidth(3.0f); glBegin(GL_LINE_LOOP);
    for (int i = 0; i < 32; ++i) { const float a = i * 6.28318530718f / 32.0f; glVertex2f(p.x + 12.0f*cosf(a), p.y + 12.0f*sinf(a)); }
    glEnd();
  }
  glPopMatrix();
  glMatrixMode(GL_PROJECTION);
  glPopMatrix();
  glMatrixMode(GL_MODELVIEW);
  glPopAttrib();
  return true;
}
