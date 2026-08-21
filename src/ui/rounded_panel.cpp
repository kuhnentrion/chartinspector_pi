#include "ui/rounded_panel.h"

#include <wx/dcbuffer.h>
#include <wx/settings.h>

namespace ci_ui {

RoundedPanel::RoundedPanel(wxWindow *parent, int radius)
    : wxPanel(parent, wxID_ANY, wxDefaultPosition, wxDefaultSize, wxBORDER_NONE),
      m_fill(wxSystemSettings::GetColour(wxSYS_COLOUR_WINDOW)),
      m_border(wxSystemSettings::GetColour(wxSYS_COLOUR_BTNSHADOW)),
      m_radius(radius) {
  SetBackgroundStyle(wxBG_STYLE_PAINT);
  Bind(wxEVT_PAINT, &RoundedPanel::OnPaint, this);
}

void RoundedPanel::SetCardColours(const wxColour &background,
                                  const wxColour &border) {
  m_fill = background;
  m_border = border;
  SetBackgroundColour(background);
  Refresh(false);
}

void RoundedPanel::SetRadius(int radius) {
  m_radius = radius;
  Refresh(false);
}

void RoundedPanel::OnPaint(wxPaintEvent &) {
  wxAutoBufferedPaintDC dc(this);
  dc.SetBackground(wxBrush(GetParent()->GetBackgroundColour()));
  dc.Clear();
  const wxSize size = GetClientSize();
  if (size.x <= 1 || size.y <= 1) return;
  dc.SetPen(wxPen(m_border, 1));
  dc.SetBrush(wxBrush(m_fill));
  dc.DrawRoundedRectangle(0, 0, size.x - 1, size.y - 1, m_radius);
}

}  // namespace ci_ui
