#ifndef CHARTINSPECTOR_UI_ROUNDED_PANEL_H
#define CHARTINSPECTOR_UI_ROUNDED_PANEL_H

#include <wx/panel.h>

namespace ci_ui {

class RoundedPanel : public wxPanel {
public:
  RoundedPanel(wxWindow *parent, int radius = 8);
  void SetCardColours(const wxColour &background, const wxColour &border);
  void SetRadius(int radius);

private:
  void OnPaint(wxPaintEvent &event);

  wxColour m_fill;
  wxColour m_border;
  int m_radius = 8;
};

}  // namespace ci_ui

#endif
