// cam-control — sleek, dark, frameless live V4L2 control panel for the
// FaceTime HD webcam. Enumerates every available control on /dev/video0, shows
// a slim slider per integer control + a toggle per boolean, applies changes LIVE
// via V4L2 ioctls, and writes ~/.config/cam-control/controls.conf so the cam-tune
// enforcer keeps them against Brave/Chromium's reset-on-open.
//
// Build:
//   g++ cam-control.cpp -o ~/.local/bin/cam-control \
//       $(pkg-config --cflags --libs gtkmm-3.0) -std=c++17

#include <gtkmm.h>
#include <gdk/gdk.h>
#include <linux/videodev2.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <cctype>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

static const char *DEVICE = "/dev/video0";

static const char *CSS = R"CSS(
window { background-color: transparent; }

.card {
  background-color: #1b1b1d;
  border-radius: 20px;
  border: 1px solid rgba(255,255,255,0.06);
  padding: 20px 22px 18px 22px;
}

.title  { color: #f4f4f5; font-weight: 600; font-size: 13pt; }
.clabel { color: #8a8a90; font-size: 9pt; }
.note   { color: #5d5d63; font-size: 8pt; }

/* slim pill sliders */
scale { padding: 6px 0; }
scale trough {
  background-color: #2c2c30;
  border-radius: 999px;
  min-height: 5px;
  border: none;
}
scale highlight {
  background-color: #e8e8ea;
  border-radius: 999px;
  border: none;
}
scale slider {
  background-color: #ffffff;
  border-radius: 999px;
  min-width: 17px; min-height: 17px;
  margin: -7px;
  box-shadow: 0 1px 4px rgba(0,0,0,0.55);
}
scale value { color: #9a9aa0; font-size: 8pt; }

/* toggle */
checkbutton { color: #d4d4d8; font-size: 10pt; }
checkbutton check {
  background-color: #2c2c30;
  border-radius: 6px;
  border: none;
  min-width: 17px; min-height: 17px;
  margin-right: 6px;
}
checkbutton check:checked { background-color: #e8e8ea; }

separator { background-color: rgba(255,255,255,0.07); min-height: 1px; margin: 4px 0; }

button {
  background-image: none;
  background-color: #2a2a2e;
  color: #e6e6e8;
  border: none;
  border-radius: 11px;
  padding: 8px 14px;
  font-size: 10pt;
}
button:hover  { background-color: #36363b; }
button:active { background-color: #444; }

.close {
  background-color: transparent;
  color: #777;
  padding: 0 6px;
  border-radius: 999px;
  font-size: 13pt;
}
.close:hover { background-color: rgba(255,255,255,0.08); color: #eee; }
)CSS";

static std::string slugify(const std::string &s) {
    std::string out; bool us = false;
    for (unsigned char c : s) {
        if (std::isalnum(c)) { out += (char)std::tolower(c); us = false; }
        else if (!out.empty() && !us) { out += '_'; us = true; }
    }
    while (!out.empty() && out.back() == '_') out.pop_back();
    return out;
}

struct Ctrl {
    __u32 id = 0, type = 0;
    std::string name, slug;
    int minimum = 0, maximum = 0, step = 1, def = 0;
    Gtk::Scale *scale = nullptr;
    Gtk::CheckButton *check = nullptr;
};

class CamWindow : public Gtk::Window {
public:
    CamWindow();
    ~CamWindow() override { if (fd >= 0) ::close(fd); }

private:
    int fd = -1;
    std::vector<Ctrl> ctrls;
    Gtk::Box card{Gtk::ORIENTATION_VERTICAL, 14};

    int  get_ctrl(__u32 id) { v4l2_control c{}; c.id = id; return ioctl(fd, VIDIOC_G_CTRL, &c) == 0 ? c.value : 0; }
    void set_ctrl(__u32 id, int v) { v4l2_control c{}; c.id = id; c.value = v; ioctl(fd, VIDIOC_S_CTRL, &c); }

    std::string home() { const char *h = getenv("HOME"); return h ? h : "."; }
    std::string config_path() { return home() + "/.config/cam-control/controls.conf"; }
    void write_config() {
        ::mkdir((home() + "/.config").c_str(), 0755);
        ::mkdir((home() + "/.config/cam-control").c_str(), 0755);
        std::ofstream f(config_path(), std::ios::trunc);
        if (!f) return;
        f << "# written by cam-control - enforced by cam-tune\n";
        for (auto &c : ctrls) f << c.slug << "=" << get_ctrl(c.id) << "\n";
    }

    void enumerate() {
        v4l2_queryctrl q{}; q.id = V4L2_CTRL_FLAG_NEXT_CTRL;
        while (ioctl(fd, VIDIOC_QUERYCTRL, &q) == 0) {
            if (!(q.flags & V4L2_CTRL_FLAG_DISABLED) &&
                (q.type == V4L2_CTRL_TYPE_INTEGER || q.type == V4L2_CTRL_TYPE_BOOLEAN)) {
                Ctrl c;
                c.id = q.id; c.type = q.type;
                c.name = reinterpret_cast<const char *>(q.name);
                c.slug = slugify(c.name);
                c.minimum = q.minimum; c.maximum = q.maximum;
                c.step = q.step ? q.step : 1; c.def = q.default_value;
                ctrls.push_back(c);
            }
            q.id |= V4L2_CTRL_FLAG_NEXT_CTRL;
        }
    }

    void build_ui();
    void on_reset();
    bool on_drag(GdkEventButton *e) {
        if (e->button == 1) begin_move_drag(e->button, e->x_root, e->y_root, e->time);
        return false;
    }
};

CamWindow::CamWindow() {
    set_title("Camera");
    set_decorated(false);
    set_resizable(false);
    set_default_size(360, -1);
    set_app_paintable(true);
    if (auto v = get_screen()->get_rgba_visual())
        gtk_widget_set_visual(GTK_WIDGET(gobj()), v->gobj());

    auto css = Gtk::CssProvider::create();
    css->load_from_data(CSS);
    Gtk::StyleContext::add_provider_for_screen(
        get_screen(), css, GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

    card.get_style_context()->add_class("card");
    add(card);

    // ESC closes
    signal_key_press_event().connect([this](GdkEventKey *e) {
        if (e->keyval == GDK_KEY_Escape) { close(); return true; }
        return false;
    });

    fd = ::open(DEVICE, O_RDWR);
    if (fd < 0) {
        auto *l = Gtk::manage(new Gtk::Label());
        l->get_style_context()->add_class("title");
        l->set_text("Camera off");
        auto *s = Gtk::manage(new Gtk::Label());
        s->get_style_context()->add_class("clabel");
        s->set_text("Run  cam-on  first.");
        card.pack_start(*l, Gtk::PACK_SHRINK);
        card.pack_start(*s, Gtk::PACK_SHRINK);
        show_all_children();
        return;
    }
    enumerate();
    build_ui();
}

void CamWindow::build_ui() {
    // header: draggable title + close
    auto *hb = Gtk::manage(new Gtk::Box(Gtk::ORIENTATION_HORIZONTAL, 8));
    auto *title = Gtk::manage(new Gtk::Label("Camera"));
    title->get_style_context()->add_class("title");
    title->set_halign(Gtk::ALIGN_START);
    auto *close_btn = Gtk::manage(new Gtk::Button("✕"));
    close_btn->get_style_context()->add_class("close");
    close_btn->set_relief(Gtk::RELIEF_NONE);
    close_btn->signal_clicked().connect([this]() { close(); });
    hb->pack_start(*title, Gtk::PACK_EXPAND_WIDGET);
    hb->pack_end(*close_btn, Gtk::PACK_SHRINK);

    auto *handle = Gtk::manage(new Gtk::EventBox());
    handle->add(*hb);
    handle->signal_button_press_event().connect(sigc::mem_fun(*this, &CamWindow::on_drag));
    card.pack_start(*handle, Gtk::PACK_SHRINK);

    for (auto &c : ctrls) {
        if (c.type == V4L2_CTRL_TYPE_INTEGER) {
            auto *col = Gtk::manage(new Gtk::Box(Gtk::ORIENTATION_VERTICAL, 2));
            auto *lbl = Gtk::manage(new Gtk::Label(c.name));
            lbl->get_style_context()->add_class("clabel");
            lbl->set_halign(Gtk::ALIGN_START);
            auto *sc = Gtk::manage(new Gtk::Scale(Gtk::ORIENTATION_HORIZONTAL));
            sc->set_range(c.minimum, c.maximum);
            sc->set_increments(c.step, c.step * 10);
            sc->set_digits(0);
            sc->set_value_pos(Gtk::POS_RIGHT);
            sc->set_hexpand(true);
            sc->set_value(get_ctrl(c.id));
            Ctrl *cp = &c;
            sc->signal_value_changed().connect([this, cp, sc]() {
                set_ctrl(cp->id, (int)sc->get_value());
                write_config();
            });
            c.scale = sc;
            col->pack_start(*lbl, Gtk::PACK_SHRINK);
            col->pack_start(*sc, Gtk::PACK_SHRINK);
            card.pack_start(*col, Gtk::PACK_SHRINK);
        } else {
            auto *chk = Gtk::manage(new Gtk::CheckButton(c.name));
            chk->set_active(get_ctrl(c.id) != 0);
            Ctrl *cp = &c;
            chk->signal_toggled().connect([this, cp, chk]() {
                set_ctrl(cp->id, chk->get_active() ? 1 : 0);
                write_config();
            });
            c.check = chk;
            card.pack_start(*chk, Gtk::PACK_SHRINK);
        }
    }

    card.pack_start(*Gtk::manage(new Gtk::Separator(Gtk::ORIENTATION_HORIZONTAL)), Gtk::PACK_SHRINK);

    auto *reset = Gtk::manage(new Gtk::Button("Reset"));
    reset->signal_clicked().connect(sigc::mem_fun(*this, &CamWindow::on_reset));
    card.pack_start(*reset, Gtk::PACK_SHRINK);

    auto *note = Gtk::manage(new Gtk::Label("live · saved · enforced"));
    note->get_style_context()->add_class("note");
    note->set_halign(Gtk::ALIGN_CENTER);
    card.pack_start(*note, Gtk::PACK_SHRINK);

    show_all_children();
    write_config();
}

void CamWindow::on_reset() {
    for (auto &c : ctrls) {
        set_ctrl(c.id, c.def);
        if (c.scale) c.scale->set_value(c.def);
        if (c.check) c.check->set_active(c.def != 0);
    }
    write_config();
}

int main(int argc, char *argv[]) {
    auto app = Gtk::Application::create(argc, argv, "org.machud.camcontrol");
    CamWindow win;
    return app->run(win);
}
