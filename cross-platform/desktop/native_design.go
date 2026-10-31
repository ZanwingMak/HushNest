package main

import (
	"fmt"
	"math"
	"runtime"
	"slices"
	"strconv"
	"time"

	"github.com/egoist/mygo"
	"github.com/egoist/mygo/ui"
)

// Original vector artwork stays in the Go binary. No web content is used.
func nestText(c *ui.Context, text string) ui.Element { return ui.Text(c, text).Font(c.Theme().Font) }
func nestButton(c *ui.Context, label string) ui.Element {
	button := ui.Button(c, "").Font(c.Theme().Font)
	if label != "" {
		button.Label(label).Children(func() { nestText(c, label) })
	}
	return button
}
func nestPrimaryButton(c *ui.Context, label string) ui.Element {
	button := ui.PrimaryButton(c, "").Font(c.Theme().Font)
	if label != "" {
		button.Label(label).Children(func() { nestText(c, label) })
	}
	return button
}
func nestSVG(paths string) *ui.SVG {
	return ui.MustParseSVG([]byte(`<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">` + paths + `</svg>`))
}

var nestIcons = map[string]*ui.SVG{
	"rest":       nestSVG(`<path d="M20 14.4A8.2 8.2 0 0 1 9.6 4 8.2 8.2 0 1 0 20 14.4Z"/><path d="M16 3v4m-2-2h4"/>`),
	"library":    nestSVG(`<path d="M5 17V7m5 13V4m5 13V7m5 7v-4"/>`),
	"history":    nestSVG(`<path d="M19.5 4.5C9 3 4 8 5.5 14.5c1 4.5 6.5 5 9.5 2S19 9 19.5 4.5Z"/><path d="m4 21 10-11"/>`),
	"settings":   nestSVG(`<path d="M4 6h4m4 0h8M4 12h10m4 0h2M4 18h2m4 0h10"/><circle cx="10" cy="6" r="2"/><circle cx="16" cy="12" r="2"/><circle cx="8" cy="18" r="2"/>`),
	"headphones": nestSVG(`<path d="M4 14v-3a8 8 0 0 1 16 0v3"/><rect x="3" y="12" width="4" height="8" rx="2"/><rect x="17" y="12" width="4" height="8" rx="2"/>`),
	"play":       nestSVG(`<path d="m9 5 11 7-11 7Z"/>`),
	"stop":       nestSVG(`<rect x="6" y="6" width="12" height="12" rx="2"/>`),
	"plus":       nestSVG(`<path d="M12 5v14M5 12h14"/>`),
	"check":      nestSVG(`<path d="m5 12 4 4L19 6"/>`),
	"shield":     nestSVG(`<path d="m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6Z"/><path d="m8 12 3 3 5-6"/>`),
	"bell":       nestSVG(`<path d="M5 17h14l-2-3V9a5 5 0 0 0-10 0v5Zm5 3h4"/>`),
	"clock":      nestSVG(`<circle cx="12" cy="12" r="9"/><path d="M12 7v6l4 2"/>`),
	"upload":     nestSVG(`<path d="M12 16V3m-4 4 4-4 4 4M4 15v5h16v-5"/>`),
	"rain":       nestSVG(`<path d="M6 13a4 4 0 0 1-.3-8 6 6 0 0 1 11 1A3.5 3.5 0 0 1 18 13M7 16l-1 3m6-3-1 3m6-3-1 3"/>`),
	"ocean":      nestSVG(`<path d="M2 7c3-5 7 5 10 0s7 5 10 0M2 12c3-5 7 5 10 0s7 5 10 0M2 17c3-5 7 5 10 0s7 5 10 0"/>`),
	"stream":     nestSVG(`<path d="M12 3C9 8 5 11 5 15a7 7 0 0 0 14 0c0-4-4-7-7-12Z"/><path d="M9 16a3 3 0 0 0 3 3"/>`),
	"forest":     nestSVG(`<path d="m12 2-6 8h3l-5 7h7v5h2v-5h7l-5-7h3Z"/>`),
	"fireplace":  nestSVG(`<path d="M12 2c1 6-5 6-3 11 2-1 3-3 3-3s6 3 6 7a6 6 0 0 1-12 0C3 11 11 9 12 2Z"/>`),
	"night":      nestSVG(`<path d="M18 14A7 7 0 0 1 10 4a8 8 0 1 0 8 10Z"/><path d="M18 3v4m-2-2h4"/>`),
	"brown":      nestSVG(`<path d="M3 10v4m4-7v10m5-14v18m5-14v10m4-7v4"/>`),
	"pink":       nestSVG(`<path d="M3 9v6m4-9v12m5-10v8m5-13v18m4-12v6"/>`),
	"none":       nestSVG(`<path d="m3 3 18 18M10 6l4-3v11M5 8H3v8h5l6 5v-3M18 7a8 8 0 0 1 2 8"/>`),
}

func nestIcon(c *ui.Context, name string, size float32, color ui.Color) {
	icon := nestIcons[name]
	if icon == nil {
		icon = nestIcons["library"]
	}
	ui.Icon(c, icon).Size(size, size).Shrink(0).TextColor(color)
}
func (a *nativeApp) theme(c *ui.Context) *ui.Theme {
	t := *c.Theme()
	if a.settings.Appearance == "light" {
		t = *ui.LightTheme()
	}
	if a.settings.Appearance == "dark" {
		t = *ui.DarkTheme()
	}
	t.FontSize, t.Spacing, t.Radius = 14, 4, 9
	if runtime.GOOS == "windows" {
		t.Font = "Microsoft YaHei UI, Segoe UI"
		switch a.preferences.Language {
		case "zh-Hans":
			t.Font = "Microsoft YaHei UI, Segoe UI"
		case "zh-Hant":
			t.Font = "Microsoft JhengHei UI"
		case "ja":
			t.Font = "Yu Gothic UI"
		case "ko":
			t.Font = "Malgun Gothic"
		}
	}
	accent := map[string]string{"pine": "#39755c", "ocean": "#426f8c", "dusk": "#78608e", "rose": "#a26377"}[a.settings.Theme]
	if t.Dark {
		t.Background, t.Surface, t.Border = ui.Hex("#17201c"), ui.Hex("#202c25"), ui.Hex("#344239")
		t.Text, t.TextMuted = ui.Hex("#e7eee5"), ui.Hex("#9aaa9d")
		accent = map[string]string{"pine": "#8fc5a0", "ocean": "#95c4dc", "dusk": "#c4addd", "rose": "#e1a5b9"}[a.settings.Theme]
		t.AccentText = ui.Hex("#17251c")
	} else {
		t.Background, t.Surface, t.Border = ui.Hex("#f7f8f4"), ui.Hex("#ffffff"), ui.Hex("#e5e9e1")
		t.Text, t.TextMuted = ui.Hex("#2b3a30"), ui.Hex("#626f63")
		t.Warning = ui.Hex("#9a6b2a")
		t.AccentText = ui.Hex("#ffffff")
	}
	t.Accent, t.Focus = ui.Hex(accent), ui.Hex(accent)
	t.AccentHover, t.AccentPressed = t.Accent.Alpha(.9), t.Accent.Alpha(.8)
	t.SurfaceHover, t.SurfacePressed = t.Accent.Alpha(.06), t.Accent.Alpha(.12)
	if a.settings.LargeText {
		t.FontSize = 17
	}
	c.SetTheme(&t)
	return &t
}
func (a *nativeApp) render(c *ui.Context) {
	t := a.theme(c)
	if a.dirty {
		if !a.busy && !time.Now().Before(a.dirtyAt) {
			a.save()
		} else {
			c.After(650 * time.Millisecond)
		}
	}
	if a.snapshot.Session != nil {
		c.After(time.Second)
	}
	width, _ := c.Size()
	compact := width < 900
	ui.Row(c).Fill().Font(t.Font).FontWeight(450).Lang(a.preferences.Language).FontSize(t.FontSize).TextColor(t.Text).AlignItems(ui.Stretch).Gap(0).Children(func() {
		if !compact {
			a.sidebar(c)
		}
		padding := float32(32)
		if compact {
			padding = 20
		}
		ui.Column(c).Grow(1).MinWidth(0).Padding(padding).Gap(22).Children(func() {
			if compact {
				a.compactNavigation(c)
			}
			a.pageHeading(c, compact)
			if a.errorText != "" {
				ui.Row(c).Gap(12).Padding(12, 16).Radius(10).Background(t.Danger.Alpha(.08)).Children(func() {
					nestText(c, a.errorText).Grow(1).TextColor(t.Danger)
					nestButton(c, "×").Label(a.t("知道了")).Border(0, ui.Transparent).OnClick(func() { a.errorText = "" })
				})
			}
			ui.Scroll(c.Key(a.page)).Grow(1).MinHeight(0).Gap(20).Padding(0, 2, 12, 0).Children(func() {
				switch a.page {
				case "rest":
					a.restPage(c)
				case "library":
					a.libraryPage(c)
				case "history":
					a.historyPage(c)
				case "settings":
					a.settingsPage(c)
				}
			})
		})
	})
	if done := a.afterRender; done != nil {
		a.afterRender = nil
		done()
	}
}

var nestPages = []soundChoice{{"rest", "休息"}, {"library", "我的声音"}, {"history", "足迹"}, {"settings", "设置"}}

func (a *nativeApp) sidebar(c *ui.Context) {
	t := c.Theme()
	background := ui.Hex("#edf0e8")
	if t.Dark {
		background = ui.Hex("#1c2720")
	}
	ui.Column(c).Width(186).Shrink(0).Padding(28, 18).Gap(32).Background(background).Children(func() {
		ui.Row(c).Gap(10).Padding(0, 10).Children(func() {
			ui.Box(c).Size(34, 34).Center().Radius(12).Background(t.Accent).Children(func() { nestIcon(c, "rest", 21, t.AccentText) })
			ui.Column(c).Gap(2).Children(func() {
				nestText(c, "HushNest").FontSize(18).FontWeight(650).LetterSpacing(-.5)
				nestText(c, a.t("片刻安静")).FontSize(11).TextColor(t.TextMuted)
			})
		})
		ui.Column(c).Gap(7).Children(func() {
			for _, page := range nestPages {
				a.navButton(c, page, false)
			}
		})
		ui.Spacer(c)
		ui.Column(c).Gap(12).Padding(0, 10).Children(func() {
			nestIcon(c, "history", 24, t.Accent.Alpha(.6))
			nestText(c, a.t("每一次停下，都是照顾自己。")).FontSize(12).LineHeight(1.8).TextColor(t.TextMuted)
			nestText(c, "HUSHNEST  /  0.3.2").FontSize(9).LetterSpacing(1.3).TextColor(t.TextMuted.Alpha(.7))
		})
	})
}
func (a *nativeApp) navButton(c *ui.Context, page soundChoice, compact bool) {
	t := c.Theme()
	selected := a.page == page.id
	button := nestButton(c.Key(page.id), "").Label(a.t(page.name)).Height(44).Gap(12).Padding(0, 14).Border(0, ui.Transparent).Background(ui.Transparent).Radius(10)
	if compact {
		button.Grow(1).Justify(ui.Center)
	}
	if selected {
		button.Background(t.Accent.Alpha(.1)).TextColor(t.Accent)
	} else {
		button.TextColor(t.TextMuted)
	}
	button.Children(func() {
		color := t.TextMuted
		if selected {
			color = t.Accent
		}
		nestIcon(c, page.id, 18, color)
		nestText(c, a.t(page.name)).FontSize(13).FontWeight(500)
	})
	button.OnClick(func() { a.page = page.id; a.errorText = "" })
}
func (a *nativeApp) compactNavigation(c *ui.Context) {
	ui.Row(c).Gap(5).Children(func() {
		for _, page := range nestPages {
			a.navButton(c, page, true)
		}
	})
}
func (a *nativeApp) pageHeading(c *ui.Context, compact bool) {
	t := c.Theme()
	title := map[string]string{"rest": "给自己，片刻安静。", "library": "我的声音", "history": "休息足迹", "settings": "按你的节奏"}[a.page]
	subtitle := map[string]string{"rest": "放下忙碌，让身心慢慢归位。", "library": "把喜欢的声音，留给安静的时刻。", "history": "每次停下来，都在好好照顾自己。", "settings": "让每一次休息，都更适合你。"}[a.page]
	ui.Row(c).Gap(16).Children(func() {
		ui.Column(c).Grow(1).Gap(7).Children(func() {
			nestText(c, a.t(title)).FontSize(26).FontWeight(600).LetterSpacing(-.5)
			nestText(c, a.t(subtitle)).FontSize(12).TextColor(t.TextMuted)
		})
		if !compact {
			ui.Row(c).Gap(6).Padding(7, 10).Radius(20).Background(t.Accent.Alpha(.055)).Children(func() {
				nestIcon(c, "shield", 13, t.Accent)
				nestText(c, a.t("仅在本机")).FontSize(11).TextColor(t.Accent)
			})
		}
	})
}
func (a *nativeApp) card(c *ui.Context, title string, content func()) {
	t := c.Theme()
	ui.Column(c).Padding(18).Gap(14).Radius(16).Background(t.Surface).Border(1, t.Border.Alpha(.8)).Children(func() {
		if title != "" {
			nestText(c, a.t(title)).FontSize(14).FontWeight(600)
		}
		content()
	})
}
func (a *nativeApp) restPage(c *ui.Context) {
	width, _ := c.Size()
	wide := width >= 1000 && !a.settings.LargeText
	if wide {
		ui.Grid(c).ColumnTracks(ui.Fr(1), ui.Fixed(296)).Gap(22).AlignItems(ui.Start).Children(func() {
			a.timerPanel(c)
			ui.Column(c).Gap(16).Children(func() {
				a.card(c, "", func() { a.routeControls(c) })
				if a.snapshot.Session == nil {
					a.durationControls(c)
				}
				a.soundPanel(c)
			})
		})
	} else {
		a.timerPanel(c)
		a.card(c, "", func() { a.routeControls(c) })
		if a.snapshot.Session == nil {
			a.durationControls(c)
		}
		a.soundPanel(c)
	}
}
func (a *nativeApp) timerPanel(c *ui.Context) {
	t := c.Theme()
	_, height := c.Size()
	short := height < 700
	dialSize, panelPadding, panelGap := float32(280), float32(28), float32(22)
	if short {
		dialSize, panelPadding, panelGap = 190, 16, 10
	}
	session := a.snapshot.Session
	remaining, fraction := float64(a.preferences.Duration), 1.0
	heading := "这一刻，只属于你"
	if session != nil {
		remaining = session.remaining(time.Now().UnixMilli())
		fraction = min(1, remaining/float64(session.Duration))
		heading = map[SessionPhase]string{PhaseResting: "安心休息，慢慢来。", PhasePaused: "休息已暂停", PhaseBlocked: "提醒已中断", PhaseRinging: "休息好啦，慢慢醒来"}[session.Phase]
	}
	background, ending := ui.Hex("#eff3e9"), ui.Hex("#f8faf5")
	if t.Dark {
		background = ui.Hex("#25372b")
		ending = ui.Hex("#213027")
	}
	ui.Column(c).Gap(0).MinWidth(0).Children(func() {
		ui.Column(c).Padding(panelPadding, 20).Gap(panelGap).Radius(22).Gradient(background, ending, 115).AlignItems(ui.Center).Children(func() {
			ui.Row(c).Gap(6).Children(func() { nestIcon(c, "rest", 14, t.Accent); nestText(c, a.t(heading)).FontSize(12).TextColor(t.Accent) })
			ui.Box(c).Size(dialSize, dialSize).Center().Draw(func(p *ui.Painter, r ui.Rect) {
				cx, cy := r.X+r.W/2, r.Y+r.H/2
				radius := r.W/2 - 14
				p.FillPath((&ui.Path{}).Circle(cx, cy, radius-13), t.Surface.Alpha(.36))
				p.StrokePath((&ui.Path{}).Circle(cx, cy, radius), 3, t.Accent.Alpha(.1))
				for i := 0; i < 60; i++ {
					angle := float64(i)*math.Pi/30 - math.Pi/2
					length := float32(2)
					if i%5 == 0 {
						length = 5
					}
					outer := radius - 13
					inner := outer - length
					p.Line(cx+outer*float32(math.Cos(angle)), cy+outer*float32(math.Sin(angle)), cx+inner*float32(math.Cos(angle)), cy+inner*float32(math.Sin(angle)), 1, t.Accent.Alpha(.22))
				}
				var arc ui.Path
				for i := 0; i <= 160; i++ {
					angle := -math.Pi/2 + 2*math.Pi*fraction*float64(i)/160
					x, y := cx+radius*float32(math.Cos(angle)), cy+radius*float32(math.Sin(angle))
					if i == 0 {
						arc.MoveTo(x, y)
					} else {
						arc.LineTo(x, y)
					}
				}
				p.StrokePath(&arc, 3, t.Accent.Alpha(.8))
			}).Children(func() {
				ui.Column(c).AlignItems(ui.Center).Gap(10).Children(func() {
					label := "倒计时"
					if a.mode == "clock" {
						label = "唤醒时间"
					}
					nestText(c, a.t(label)).FontSize(11).LetterSpacing(1.5).TextColor(t.TextMuted)
					text := clockText(remaining)
					if session == nil && a.mode == "clock" {
						text = a.target.Format("15:04")
					}
					size := float32(58)
					if short {
						size = 44
					}
					if len(text) > 5 {
						size = 43
						if short {
							size = 31
						}
					}
					if session != nil && session.Phase == PhaseRinging {
						text = a.t("时间到了")
						size = 32
					}
					nestText(c, text).Font("Segoe UI, system-ui").FontFeatures("tnum").FontSize(size).FontWeight(350).LetterSpacing(-2)
					wake := time.Now().Add(time.Duration(remaining) * time.Second).Format("15:04")
					if session == nil && a.mode == "clock" {
						wake = a.target.Format("15:04")
					}
					if session != nil {
						wake = time.UnixMilli(session.Deadline).Local().Format("15:04")
					}
					ui.Row(c).Gap(5).Children(func() {
						nestIcon(c, "bell", 12, t.TextMuted)
						nestText(c, wake+"  "+a.t("轻轻唤醒")).FontSize(11).TextColor(t.TextMuted)
					})
				})
			})
			if session == nil {
				ui.Row(c).Gap(6).Wrap().Justify(ui.Center).MaxWidth(330).Children(func() {
					for _, duration := range a.settings.Presets {
						button := nestButton(c.Key(duration), clockText(float64(duration))).Height(32).Padding(0, 12).Radius(16).FontSize(11).Border(0, ui.Transparent).Background(t.Surface.Alpha(.65)).Disabled(a.busy)
						if duration == a.preferences.Duration {
							button.Background(t.Accent.Alpha(.12)).TextColor(t.Accent)
						}
						button.OnClick(func() { a.setDuration(duration); a.changed() })
					}
				})
			}
			a.timerActions(c)
			if session != nil && session.Phase == PhaseBlocked {
				key := "当前没有可用耳机，声音已停止。连接后请手动继续。"
				if session.Reason != nil && *session.Reason == "restored" {
					key = "应用曾被关闭或系统结束，提醒未在后台继续。请确认耳机后手动恢复。"
				}
				if session.Reason != nil && *session.Reason == "audioError" {
					key = "声音已停止，请检查耳机或重新选择声音。"
				}
				nestText(c, a.t(key)).FontSize(12).MaxWidth(330).TextAlign(ui.Center).TextColor(t.Warning)
			}
			if a.busy {
				nestText(c, a.t("正在准备…")).FontSize(11).TextColor(t.TextMuted)
			} else {
				nestText(c, a.t("助眠声音 · 渐强唤醒")).FontSize(11).TextColor(t.TextMuted)
			}
		})
		ui.Row(c).Gap(6).Padding(12, 6, 0, 6).Justify(ui.Center).Children(func() {
			nestIcon(c, "shield", 12, t.TextMuted)
			nestText(c, a.t("休息期间保持运行，关窗可收至托盘。")).FontSize(10).TextColor(t.TextMuted)
		})
	})
}
func (a *nativeApp) timerActions(c *ui.Context) {
	t := c.Theme()
	s := a.snapshot.Session
	ui.Column(c).AlignItems(ui.Center).Gap(10).Children(func() {
		if s == nil {
			nestPrimaryButton(c, "").Label(a.t("开始休息")).Height(46).Width(236).Radius(23).Gap(10).Justify(ui.Center).Disabled(a.busy).Children(func() {
				nestIcon(c, "play", 15, t.AccentText)
				nestText(c, a.t("开始休息")).FontSize(14).FontWeight(500)
			}).OnClick(a.begin)
		} else {
			label, action := "暂停一下", "pause"
			if s.Phase == PhasePaused || s.Phase == PhaseBlocked {
				label, action = "确认耳机，继续休息", "resume"
			}
			if s.Phase == PhaseRinging {
				label, action = a.t("再休息 %@ 分钟", a.preferences.SnoozeMinutes), "snooze"
			}
			nestPrimaryButton(c, a.t(label)).Height(44).MaxWidth(300).Radius(22).Disabled(a.busy).OnClick(func() { a.command(action, 0, "") })
			nestButton(c, a.t("结束休息")).Background(ui.Transparent).Border(0, ui.Transparent).FontSize(12).TextColor(t.TextMuted).Disabled(a.busy).OnClick(func() {
				if a.ask("结束这次休息？", "结束休息") {
					a.command("stop", 0, "")
				}
			})
		}
	})
}
func (a *nativeApp) routeControls(c *ui.Context) {
	t, route := c.Theme(), a.snapshot.Route
	label, color := "尚未连接耳机", t.TextMuted
	if !route.Connected && route.Token != "" && route.RequiresConfirmation {
		label = "尚未识别到耳机"
	}
	if route.Connected {
		label, color = "耳机已就绪", t.Accent
		if !route.Verified {
			label = "耳机已手动确认"
		}
	}
	ui.Row(c).Gap(11).Children(func() {
		ui.Box(c).Size(36, 36).Radius(12).Center().Background(t.Accent.Alpha(.07)).Children(func() { nestIcon(c, "headphones", 19, t.Accent) })
		ui.Column(c).Grow(1).Gap(4).Children(func() {
			nestText(c, a.t(label)).FontSize(12).FontWeight(500).TextColor(color)
			name := route.Name
			if name == "" {
				name = a.t("连接耳机，再安心休息")
			}
			nestText(c, name).FontSize(10).TextColor(t.TextMuted).SingleLine()
		})
	})
	nestButton(c, a.t("检查耳机")).Height(30).FontSize(11).Background(ui.Transparent).TextColor(t.TextMuted).Border(1, t.Border).Disabled(a.busy).OnClick(a.checkRoute)
	if route.RequiresConfirmation && !route.Connected {
		nestText(c, a.t("无法自动识别？可手动确认当前输出是耳机。")).FontSize(11).TextColor(t.TextMuted)
		nestButton(c, a.t("确认这是耳机")).Disabled(a.busy).OnClick(func() {
			a.confirmCurrentRoute()
		})
	}
}
func (a *nativeApp) durationControls(c *ui.Context) {
	a.card(c, "按你的节奏", func() {
		t := c.Theme()
		ui.Row(c).Gap(4).Padding(3).Radius(9).Background(t.Accent.Alpha(.045)).Children(func() {
			for _, mode := range []soundChoice{{"countdown", "倒计时"}, {"clock", "指定时间"}} {
				button := nestButton(c.Key(mode.id), a.t(mode.name)).Grow(1).Height(31).FontSize(11).Border(0, ui.Transparent).Background(ui.Transparent).TextColor(t.TextMuted).Disabled(a.busy)
				if a.mode == mode.id {
					button.Background(t.Surface).TextColor(t.Accent)
				}
				button.OnClick(func() { a.mode = mode.id })
			}
		})
		if a.mode == "clock" {
			ui.TimeInput(c, &a.target).Label(a.t("唤醒时间")).Disabled(a.busy).Height(38)
		} else {
			ui.Row(c).Gap(14).Children(func() {
				a.durationField(c, "分钟", &a.minutes, 0, 720)
				nestText(c, ":").FontSize(25).TextColor(t.TextMuted)
				a.durationField(c, "秒", &a.seconds, 0, 59)
			})
			nestButton(c, "").Label(a.t("添加常用时长")).Gap(6).Justify(ui.Center).Height(29).FontSize(10).Background(ui.Transparent).Border(0, ui.Transparent).TextColor(t.TextMuted).Disabled(a.busy || slices.Contains(a.settings.Presets, a.preferences.Duration)).Children(func() { nestIcon(c, "plus", 12, t.TextMuted); nestText(c, a.t("添加常用时长")) }).OnClick(func() { a.settings.Presets = append(a.settings.Presets, a.preferences.Duration); a.changed() })
		}
	})
}
func (a *nativeApp) durationField(c *ui.Context, label string, value *float64, low, high float64) {
	t := c.Theme()
	draft := &a.minuteDraft
	if label == "秒" {
		draft = &a.secondDraft
	}
	ui.Column(c).Grow(1).Gap(6).Children(func() {
		if ui.TextInput(c.Key(label), draft).Label(a.t(label)).Font("Segoe UI, system-ui").FontSize(22).FontFeatures("tnum").Height(43).Padding(7, 12).Background(t.Background).Border(1, t.Border).Disabled(a.busy).Changed() {
			if number, err := strconv.Atoi(*draft); err == nil && float64(number) >= low && float64(number) <= high {
				*value = float64(number)
				if duration := int(a.minutes)*60 + int(a.seconds); duration >= 1 && duration <= 43200 {
					a.preferences.Duration = duration
					a.changed()
				}
			}
		}
		nestText(c, a.t(label)).FontSize(10).TextColor(t.TextMuted)
	})
}
func (a *nativeApp) soundPanel(c *ui.Context) {
	active := a.snapshot.Session != nil
	a.card(c, "声音与唤醒", func() {
		a.soundSelector(c, "助眠音", &a.preferences.SleepSound, sleepChoices, active)
		a.volume(c, "助眠音量", &a.preferences.SleepVolume, .01, .6)
		ui.Divider(c).Background(c.Theme().Border.Alpha(.7))
		a.soundSelector(c, "唤醒铃声", &a.preferences.AlarmSound, alarmChoices, active)
		a.volume(c, "唤醒铃声音量", &a.preferences.AlarmVolume, .05, 1)
	})
}
func (a *nativeApp) soundSelector(c *ui.Context, label string, value *string, choices []soundChoice, active bool) {
	choices = slices.Clone(choices)
	for _, item := range a.settings.Media {
		choices = append(choices, soundChoice{"custom:" + item.ID, item.Name})
	}
	t := c.Theme()
	ui.Column(c).Gap(8).Children(func() {
		ui.Row(c).Gap(6).Children(func() {
			icon := "library"
			if label == "唤醒铃声" {
				icon = "bell"
			}
			nestIcon(c, icon, 13, t.TextMuted)
			nestText(c, a.t(label)).FontSize(11).TextColor(t.TextMuted)
		})
		ui.Row(c).Gap(7).Children(func() {
			if a.selectChoice(c, label, value, choices, active || a.busy).Height(35).FontSize(12).Changed() {
				a.changed()
			}
			a.previewButton(c.Key(label+"-preview"), *value, a.t(label), label == "唤醒铃声", active || a.busy || *value == "none", 34)
		})
	})
}
func (a *nativeApp) previewButton(c *ui.Context, sound, label string, alarm, disabled bool, size float32) {
	t := c.Theme()
	icon, title := "play", a.t("试听")
	playing := a.snapshot.PreviewSound == sound && sound != ""
	if playing {
		icon, title = "stop", a.t("停止试听")
	}
	button := nestButton(c, "").Label(title+" "+label).Tooltip(title).Size(size, size).Padding(0).Justify(ui.Center).Background(t.Background).Border(1, t.Border).Disabled(disabled)
	if playing {
		button.Background(t.Accent.Alpha(.12)).Border(1, t.Accent.Alpha(.5))
	}
	button.Children(func() { nestIcon(c, icon, 14, t.Accent) }).OnClick(func() { a.command("preview", 0, sound, alarm) })
}
func (a *nativeApp) selectChoice(c *ui.Context, label string, value *string, choices []soundChoice, disabled bool) ui.Element {
	names := make([]string, len(choices))
	selected := ""
	seen := map[string]bool{}
	for i, choice := range choices {
		names[i] = a.t(choice.name)
		if seen[names[i]] {
			names[i] += " · " + choice.id[max(0, len(choice.id)-8):]
		}
		seen[names[i]] = true
		if choice.id == *value {
			selected = names[i]
		}
	}
	if selected == "" {
		selected = a.t("自定义声音")
	}
	element := ui.Select(c.Key(label), &selected, names).Font(c.Theme().Font).Label(a.t(label)).Grow(1).Disabled(disabled).Background(c.Theme().Background).Border(1, c.Theme().Border)
	if element.Changed() {
		for i, name := range names {
			if name == selected {
				*value = choices[i].id
				break
			}
		}
	}
	return element
}
func (a *nativeApp) volume(c *ui.Context, label string, value *float64, low, high float64) {
	t := c.Theme()
	ui.Row(c).Gap(8).Children(func() {
		if ui.Slider(c, value, low, high).Label(a.t(label)).Grow(1).Disabled(a.busy).Changed() {
			a.changed()
		}
		nestText(c, fmt.Sprintf("%d%%", int(math.Round(*value*100)))).FontSize(10).FontFeatures("tnum").TextColor(t.TextMuted).Width(30).TextAlign(ui.End)
	})
}
func (a *nativeApp) libraryPage(c *ui.Context) {
	t := c.Theme()
	width, _ := c.Size()
	columns := 3
	if width < 900 {
		columns = 2
	}
	ui.Row(c).Children(func() {
		nestText(c, a.t("自然声景")).FontSize(14).FontWeight(600).Grow(1)
		nestText(c, a.t("选择一种声音，慢慢放松。")).FontSize(11).TextColor(t.TextMuted)
	})
	ui.Grid(c).Columns(columns).Gap(12).Children(func() {
		for _, sound := range sleepChoices[1:] {
			selected := a.preferences.SleepSound == sound.id
			ui.Column(c.Key(sound.id)).Padding(18).Gap(16).Radius(14).Background(t.Surface).Border(1, t.Border).Children(func() {
				ui.Row(c).Children(func() {
					ui.Box(c).Size(38, 38).Center().Radius(12).Background(t.Accent.Alpha(.08)).Children(func() { nestIcon(c, sound.id, 21, t.Accent) })
					ui.Spacer(c)
					if selected {
						nestIcon(c, "check", 16, t.Accent)
					}
				})
				nestText(c, a.t(sound.name)).FontSize(14).FontWeight(500)
				ui.Row(c).Gap(6).Children(func() {
					label := "设为助眠音"
					if selected {
						label = "已选择"
					}
					nestButton(c, a.t(label)).Height(29).Grow(1).FontSize(10).Background(t.Accent.Alpha(.07)).Border(0, ui.Transparent).TextColor(t.Accent).Disabled(a.busy || a.snapshot.Session != nil).OnClick(func() { a.preferences.SleepSound = sound.id; a.changed() })
					a.previewButton(c, sound.id, a.t(sound.name), false, a.busy || a.snapshot.Session != nil, 29)
				})
			})
		}
	})
	ui.Row(c).Margin(10, 0, 0, 0).Children(func() {
		nestText(c, a.t("我的声音")).FontSize(14).FontWeight(600).Grow(1)
		nestButton(c, "").Label(a.t("从文件导入音频或视频")).Gap(6).Height(33).Background(t.Surface).Border(1, t.Border).Disabled(a.busy || a.snapshot.Session != nil || len(a.settings.Media) >= 20).Children(func() { nestIcon(c, "plus", 14, t.Accent); nestText(c, a.t("导入声音")).FontSize(11) }).OnClick(a.chooseMedia)
	})
	if len(a.settings.Media) == 0 {
		a.card(c, "", func() {
			ui.Row(c).Gap(18).Padding(10, 4).Children(func() {
				nestIcon(c, "upload", 28, t.Accent.Alpha(.65))
				ui.Column(c).Gap(6).Children(func() {
					nestText(c, a.t("把喜欢的声音，留给安静的时刻。")).FontSize(13)
					nestText(c, a.t("支持音频与视频 · 文件仅保存在本机")).FontSize(11).TextColor(t.TextMuted)
				})
			})
		})
	} else {
		for _, item := range a.settings.Media {
			a.mediaRow(c, item)
		}
	}
	nestText(c, a.t("最多 20 个文件，每个 200 MB / 2 小时。")).FontSize(10).TextColor(t.TextMuted)
}
func (a *nativeApp) mediaRow(c *ui.Context, item localMedia) {
	t := c.Theme()
	disabled := a.busy || a.snapshot.Session != nil
	ui.Row(c.Key(item.ID)).Gap(14).Padding(16).Radius(12).Background(t.Surface).Border(1, t.Border).Wrap().Children(func() {
		nestIcon(c, "library", 20, t.Accent)
		ui.Column(c).Grow(1).Gap(5).Children(func() {
			nestText(c, item.Name).FontSize(12).FontWeight(500).SingleLine()
			nestText(c, clockText(item.Seconds)+" · "+strconv.FormatFloat(float64(item.Size)/1024/1024, 'f', 1, 64)+" MB").FontSize(10).TextColor(t.TextMuted)
		})
		ui.Row(c).Gap(7).Children(func() {
			nestButton(c, a.t("助眠音")).FontSize(10).Disabled(disabled).OnClick(func() { a.preferences.SleepSound = "custom:" + item.ID; a.changed() })
			nestButton(c, a.t("唤醒铃声")).FontSize(10).Disabled(disabled).OnClick(func() { a.preferences.AlarmSound = "custom:" + item.ID; a.changed() })
			a.previewButton(c, "custom:"+item.ID, item.Name, false, disabled, 29)
			nestButton(c, a.t("删除声音")).FontSize(10).Background(ui.Transparent).Border(0, ui.Transparent).TextColor(t.TextMuted).Disabled(disabled).OnClick(func() { a.removeMedia(item.ID) })
		})
	})
}
func (a *nativeApp) historyPage(c *ui.Context) {
	t := c.Theme()
	completed, total := 0, 0
	for _, r := range a.snapshot.Records {
		if r.Completed {
			completed++
		}
		total += r.Seconds
	}
	ui.Grid(c).Columns(2).Gap(16).Children(func() {
		a.statTile(c, "history", "完成休息", completed)
		a.statTile(c, "clock", "累计分钟", total/60)
	})
	if len(a.snapshot.Records) == 0 {
		ui.Column(c).AlignItems(ui.Center).Padding(60, 24).Gap(16).Children(func() {
			ui.Box(c).Size(70, 70).Radius(35).Center().Background(t.Accent.Alpha(.06)).Children(func() { nestIcon(c, "history", 30, t.Accent.Alpha(.7)) })
			nestText(c, a.t("从片刻安静开始")).FontSize(18).FontWeight(500)
			nestText(c, a.t("结束一次休息后，足迹会出现在这里。")).FontSize(12).TextColor(t.TextMuted)
		})
	} else {
		a.card(c, "休息足迹", func() {
			for _, record := range a.snapshot.Records {
				ui.Row(c.Key(record.ID)).Gap(16).Padding(12, 0).BorderWidth(0, 0, 1, 0).BorderColor(t.Border).Children(func() {
					icon := "history"
					label := "提前结束"
					if record.Completed {
						label = "完成一段休息"
					}
					nestIcon(c, icon, 17, t.Accent)
					ui.Column(c).Grow(1).Gap(5).Children(func() {
						nestText(c, a.t(label)).FontSize(12)
						nestText(c, time.UnixMilli(record.StartedAt).Local().Format("2006-01-02  15:04")).FontSize(10).TextColor(t.TextMuted)
					})
					nestText(c, clockText(float64(record.Seconds))).Font("Segoe UI, system-ui").FontSize(21).FontWeight(400)
				})
			}
		})
	}
	ui.Row(c).Gap(8).Children(func() {
		nestIcon(c, "shield", 12, t.TextMuted)
		nestText(c, a.t("文件和记录仅保存在这台设备上。")).FontSize(10).TextColor(t.TextMuted).Grow(1)
		nestButton(c, a.t("清空本机记录")).FontSize(10).Background(ui.Transparent).TextColor(t.TextMuted).Border(0, ui.Transparent).Disabled(a.busy || len(a.snapshot.Records) == 0 || a.snapshot.Session != nil).OnClick(func() {
			if a.ask("清空所有休息记录？", "清空记录") {
				a.command("clearRecords", 0, "")
			}
		})
	})
}
func (a *nativeApp) statTile(c *ui.Context, icon, title string, value int) {
	t := c.Theme()
	a.card(c, "", func() {
		ui.Row(c).Gap(8).Children(func() { nestIcon(c, icon, 16, t.Accent); nestText(c, a.t(title)).FontSize(12).TextColor(t.TextMuted) })
		nestText(c, strconv.Itoa(value)).Font("Segoe UI, system-ui").FontSize(39).FontWeight(350).TextColor(t.Text)
	})
}
func (a *nativeApp) settingsPage(c *ui.Context) {
	t := c.Theme()
	a.card(c, "心情与色彩", func() {
		ui.Row(c).Gap(12).Wrap().Children(func() {
			for _, choice := range []soundChoice{{"pine", "松林"}, {"ocean", "海湾"}, {"dusk", "暮紫"}, {"rose", "玫瑰"}} {
				color := map[string]string{"pine": "#39755c", "ocean": "#426f8c", "dusk": "#78608e", "rose": "#a26377"}[choice.id]
				button := nestButton(c.Key(choice.id), "").Label(a.t(choice.name)).Gap(9).Padding(9, 15).Border(1, t.Border).Background(t.Background).Disabled(a.busy)
				if a.settings.Theme == choice.id {
					button.Border(1, t.Accent).Background(t.Accent.Alpha(.07))
				}
				button.Children(func() {
					ui.Box(c).Size(14, 14).Radius(7).Background(ui.Hex(color))
					nestText(c, a.t(choice.name)).FontSize(12)
				})
				button.OnClick(func() { a.settings.Theme = choice.id; a.changed() })
			}
		})
		ui.Row(c).Gap(20).Children(func() {
			nestText(c, a.t("外观")).Width(120).FontSize(12)
			if a.selectChoice(c, "外观", &a.settings.Appearance, []soundChoice{{"system", "跟随系统"}, {"light", "浅色"}, {"dark", "深色"}}, a.busy).Height(36).Changed() {
				a.changed()
			}
		})
		if ui.Checkbox(c, &a.settings.LargeText, a.t("大字体")).Disabled(a.busy).Changed() {
			a.changed()
		}
	})
	a.card(c, "语言", func() {
		choices := make([]soundChoice, len(languageIDs))
		for i, id := range languageIDs {
			choices[i] = soundChoice{id, languageNames[i]}
		}
		language := a.preferences.Language
		if a.selectChoice(c, "语言", &language, choices, a.busy).Height(36).Changed() {
			a.preferences.Language = language
			if a.window != nil {
				mygo.App.SetLocale(language)
			}
			a.changed()
		}
	})
	a.card(c, "唤醒铃声", func() {
		if ui.Checkbox(c, &a.preferences.RepeatAlarm, a.t("持续响铃直到手动结束")).Disabled(a.busy || a.snapshot.Session != nil).Changed() {
			a.changed()
		}
		nestText(c, a.t("关闭时最多响铃 3 分钟。")).FontSize(11).TextColor(t.TextMuted)
		snooze := float64(a.preferences.SnoozeMinutes)
		ui.Row(c).Gap(12).Children(func() {
			nestText(c, a.t("稍后提醒")).FontSize(12).Width(120)
			if ui.NumberInput(c, &snooze, 1, 30, 1).Label(a.t("稍后提醒")).Disabled(a.busy || a.snapshot.Session != nil).Changed() {
				a.preferences.SnoozeMinutes = int(snooze)
				a.changed()
			}
			nestText(c, a.t("分钟")).FontSize(12).TextColor(t.TextMuted)
		})
	})
	a.card(c, "自定义时长和预设", func() {
		for _, seconds := range a.settings.Presets {
			ui.Row(c.Key(seconds)).Gap(12).Children(func() {
				nestText(c, clockText(float64(seconds))).FontFeatures("tnum").FontSize(14).Grow(1)
				nestButton(c, a.t("移除预设")).FontSize(11).Background(ui.Transparent).Border(0, ui.Transparent).TextColor(t.TextMuted).Disabled(a.busy).OnClick(func() {
					a.settings.Presets = slices.DeleteFunc(a.settings.Presets, func(n int) bool { return n == seconds })
					a.changed()
				})
			})
		}
	})
	nestPrimaryButton(c, a.t("保存配置")).Height(39).MaxWidth(160).Disabled(a.busy).OnClick(a.save)
	ui.Row(c).Gap(10).Children(func() {
		nestIcon(c, "shield", 14, t.TextMuted)
		nestText(c, a.t("免费 · 无广告 · 无订阅 · 数据仅在本机")).FontSize(10).TextColor(t.TextMuted).Grow(1)
		nestButton(c, "GitHub ↗").Label(a.t("查看开源代码")).FontSize(11).Background(ui.Transparent).Border(0, ui.Transparent).TextColor(t.TextMuted).OnClick(func() { go func() { _ = mygo.Shell.OpenExternal("https://github.com/ZanwingMak/HushNest") }() })
	})
}
