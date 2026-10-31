package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

type localMedia struct {
	ID      string
	Name    string
	Seconds float64
	Size    int64
}
type nativeSettings struct {
	Theme      string
	Appearance string
	LargeText  bool
	Presets    []int
	Media      []localMedia
}

func defaultNativeSettings() nativeSettings {
	return nativeSettings{Theme: "pine", Appearance: "system", Presets: []int{900, 1800, 2700, 3600}, Media: []localMedia{}}
}
func loadNativeSettings(directory string) (nativeSettings, error) {
	p := defaultNativeSettings()
	data, err := os.ReadFile(filepath.Join(directory, "native-ui.json"))
	if os.IsNotExist(err) {
		return p, nil
	}
	if err != nil {
		return p, err
	}
	if err = json.Unmarshal(data, &p); err != nil {
		return defaultNativeSettings(), err
	}
	if !slices.Contains([]string{"pine", "ocean", "dusk", "rose"}, p.Theme) {
		p.Theme = "pine"
	}
	if !slices.Contains([]string{"system", "light", "dark"}, p.Appearance) {
		p.Appearance = "system"
	}
	p.Presets = slices.DeleteFunc(p.Presets, func(n int) bool { return n < 1 || n > 43200 })
	p.Presets = slices.Compact(p.Presets)
	seen := map[string]bool{}
	p.Media = slices.DeleteFunc(p.Media, func(m localMedia) bool {
		if !validID(m.ID) || seen[m.ID] || m.Size < 1 || m.Size > 200*1024*1024 || m.Seconds <= 0 || m.Seconds > 7200 {
			return true
		}
		seen[m.ID] = true
		return false
	})
	if len(p.Media) > 20 {
		p.Media = p.Media[:20]
	}
	return p, nil
}
func (p nativeSettings) clone() nativeSettings {
	p.Presets = slices.Clone(p.Presets)
	p.Media = slices.Clone(p.Media)
	return p
}
func saveNativeSettings(directory string, settings nativeSettings) error {
	data, err := json.Marshal(settings)
	if err != nil {
		return err
	}
	file := filepath.Join(directory, "native-ui.json")
	if err = os.WriteFile(file+".tmp", data, 0600); err != nil {
		return err
	}
	return replaceFile(file+".tmp", file)
}

// Native file pickers supply paths only to Go. The decoder only sees a private
// UUID path, never the arbitrary path the user selected. No sound is played.
func (s *restService) importNativeMedia(source string, existing []localMedia) (item localMedia, err error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.state.Session != nil {
		return item, errors.New("session-active")
	}
	if len(existing) >= 20 {
		return item, errors.New("media-limit")
	}
	input, err := os.Open(source)
	if err != nil {
		return item, err
	}
	defer input.Close()
	info, err := input.Stat()
	if err != nil {
		return item, err
	}
	if !info.Mode().IsRegular() || info.Size() < 1 || info.Size() > 200*1024*1024 {
		return item, errors.New("media-size")
	}
	item = localMedia{ID: newID(), Name: filepath.Base(source), Size: info.Size()}
	runes := []rune(item.Name)
	if len(runes) > 160 {
		item.Name = string(runes[:160])
	}
	file, _ := s.mediaPath(item.ID, false)
	temporary, _ := s.mediaPath(item.ID, true)
	output, err := os.OpenFile(temporary, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return item, err
	}
	defer func() {
		_ = os.Remove(temporary)
		if err != nil {
			_ = os.Remove(file)
		}
	}()
	written, copyErr := io.Copy(output, io.LimitReader(input, 200*1024*1024+1))
	closeErr := output.Close()
	if copyErr != nil {
		return item, copyErr
	}
	if closeErr != nil {
		return item, closeErr
	}
	if written != info.Size() {
		return item, errors.New("media-size")
	}
	if err = replaceFile(temporary, file); err != nil {
		return item, err
	}
	var metadata struct{ Seconds float64 }
	if err = s.backend.request("inspect", map[string]any{"sound": "custom:" + item.ID}, &metadata); err != nil {
		return item, err
	}
	if !(metadata.Seconds > 0 && metadata.Seconds <= 7200) {
		return item, errors.New("media-duration")
	}
	item.Seconds = metadata.Seconds
	return item, nil
}

func nextNativeDuration(now, target time.Time) (int, error) {
	next := time.Date(now.Year(), now.Month(), now.Day(), target.Hour(), target.Minute(), 0, 0, now.Location())
	if !next.After(now) {
		next = next.AddDate(0, 0, 1)
	}
	seconds := int(next.Sub(now).Seconds() + 0.999)
	if seconds < 1 || seconds > 43200 {
		return 0, errors.New("invalid-time")
	}
	return seconds, nil
}
func clockText(seconds float64) string {
	n := max(0, int(seconds+0.999))
	if n >= 3600 {
		return fmt.Sprintf("%02d:%02d:%02d", n/3600, n/60%60, n%60)
	}
	return fmt.Sprintf("%02d:%02d", n/60, n%60)
}
func loadDictionaries(resources string) (map[string]map[string]string, error) {
	dictionaries := map[string]map[string]string{}
	for _, language := range languageIDs {
		data, err := os.ReadFile(filepath.Join(resources, "locales", language+".json"))
		if err != nil {
			return nil, err
		}
		var dictionary map[string]string
		if err = json.Unmarshal(data, &dictionary); err != nil {
			return nil, err
		}
		dictionaries[language] = dictionary
	}
	return dictionaries, nil
}

var languageIDs = []string{"zh-Hans", "zh-Hant", "en", "ja", "ko", "es"}
var languageNames = []string{"简体中文", "繁體中文", "English", "日本語", "한국어", "Español"}

// Extra desktop copy supplements the original six translation dictionaries.
var desktopCopy = map[string][6]string{
	"片刻安静": {"片刻安静", "片刻安靜", "A quiet moment", "静かなひととき", "고요한 순간", "Un momento de calma"},
	"每一次停下，都是照顾自己。":   {"每一次停下，都是照顾自己。", "每一次停下，都是照顧自己。", "A little pause. A little care.", "ひと休みが、自分へのいたわり。", "잠시 멈추는 것도 나를 돌보는 일.", "Una pausa también es cuidarte."},
	"放下忙碌，让身心慢慢归位。":   {"放下忙碌，让身心慢慢归位。", "放下忙碌，讓身心慢慢歸位。", "Let the day settle. Find your quiet.", "忙しさを手放し、心と体を整える。", "바쁨을 내려놓고 편안하게 쉬세요.", "Deja atrás las prisas. Encuentra tu calma."},
	"把喜欢的声音，留给安静的时刻。": {"把喜欢的声音，留给安静的时刻。", "把喜歡的聲音，留給安靜的時刻。", "Your favorite sounds, for quieter moments.", "好きな音で、静かなひとときを。", "좋아하는 소리와 함께 고요한 시간을.", "Tus sonidos favoritos para momentos tranquilos."},
	"每次停下来，都在好好照顾自己。": {"每次停下来，都在好好照顾自己。", "每次停下來，都在好好照顧自己。", "Every pause is a little care for yourself.", "ひと休みするたびに、自分を大切に。", "쉴 때마다 나를 돌보고 있어요.", "Cada pausa es una forma de cuidarte."},
	"让每一次休息，都更适合你。":   {"让每一次休息，都更适合你。", "讓每一次休息，都更適合你。", "Make each rest feel a little more like you.", "自分に合った休憩を。​", "나에게 꼭 맞는 휴식을 설정하세요.", "Haz que cada descanso se adapte a ti."},
	"仅在本机": {"仅在本机", "僅在本機", "On your device", "この端末のみ", "이 기기에만", "Solo en tu dispositivo"},
	"休息期间保持运行，关窗可收至托盘。": {"休息期间保持运行，关窗可收至托盘。", "休息期間保持執行，關閉視窗可收至系統匣。", "Keep running during rest. Close to the tray.", "休憩中は起動したまま。閉じるとトレイへ。", "휴식 중에는 실행을 유지하세요. 창을 닫으면 트레이로.", "Mantén la app abierta. Cerrar la envía a la bandeja."},
	"自然声景":         {"自然声景", "自然聲景", "Nature sounds", "自然の音", "자연의 소리", "Sonidos naturales"},
	"选择一种声音，慢慢放松。": {"选择一种声音，慢慢放松。", "選擇一種聲音，慢慢放鬆。", "Find a sound. Settle in.", "音を選んで、ゆっくりくつろぐ。", "소리를 고르고 편안하게 쉬세요.", "Elige un sonido y relájate."},
	"设为助眠音":        {"设为助眠音", "設為助眠音", "Use for rest", "休憩に使う", "휴식 소리로", "Usar para descansar"},
	"已选择":          {"已选择", "已選擇", "Selected", "選択中", "선택됨", "Seleccionado"},
	"导入声音":         {"导入声音", "匯入聲音", "Import sound", "音を読み込む", "소리 가져오기", "Importar sonido"},
	"支持音频与视频 · 文件仅保存在本机":          {"支持音频与视频 · 文件仅保存在本机", "支援音訊與影片 · 檔案僅儲存在本機", "Audio and video · Files stay on your device", "音声・動画に対応 · ファイルは端末内のみ", "오디오 및 동영상 · 파일은 기기에만 저장", "Audio y vídeo · Archivos locales"},
	"最多 20 个文件，每个 200 MB / 2 小时。": {"最多 20 个文件，每个 200 MB / 2 小时。", "最多 20 個檔案，每個 200 MB / 2 小時。", "Up to 20 files, 200 MB / 2 hours each.", "最大20件、各200 MB・2時間まで。", "최대 20개, 각 200 MB / 2시간.", "Hasta 20 archivos, 200 MB / 2 horas cada uno."},
	"持续响铃直到手动结束":                  {"持续响铃直到手动结束", "持續響鈴直到手動結束", "Ring until stopped", "停止するまで鳴らす", "멈출 때까지 울리기", "Sonar hasta detener"},
	"关闭时最多响铃 3 分钟。":               {"关闭时最多响铃 3 分钟。", "關閉時最多響鈴 3 分鐘。", "When off, rings for up to 3 minutes.", "オフの場合は最大3分間鳴ります。", "끄면 최대 3분 동안 울립니다.", "Si está desactivado, suena hasta 3 minutos."},
	"稍后提醒":                        {"稍后提醒", "稍後提醒", "Snooze", "スヌーズ", "다시 알림", "Posponer"},
	"唤醒铃声音量":                      {"唤醒铃声音量", "喚醒鈴聲音量", "Alarm volume", "アラーム音量", "알람 음량", "Volumen de alarma"},
	"保存配置":                        {"保存配置", "儲存設定", "Save settings", "設定を保存", "설정 저장", "Guardar ajustes"},
	"浅色":                          {"浅色", "淺色", "Light", "ライト", "라이트", "Claro"},
	"深色":                          {"深色", "深色", "Dark", "ダーク", "다크", "Oscuro"},
	"外观":                          {"外观", "外觀", "Appearance", "外観", "화면 모드", "Apariencia"},
	"大字体":                         {"大字体", "大字體", "Larger text", "大きな文字", "큰 글씨", "Texto grande"},
	"减少动态效果":                      {"减少动态效果", "減少動態效果", "Reduce motion", "視差効果を減らす", "동작 줄이기", "Reducir movimiento"},
	"小时":                          {"小时", "小時", "hours", "時間", "시간", "horas"},
	"秒":                           {"秒", "秒", "seconds", "秒", "초", "segundos"},
	"试听":                          {"试听", "試聽", "Preview", "試聴", "미리 듣기", "Escuchar"},
	"移除预设":                        {"移除预设", "移除預設", "Remove preset", "プリセットを削除", "프리셋 삭제", "Quitar preajuste"},
	"检查耳机":                        {"检查耳机", "檢查耳機", "Check headphones", "イヤホンを確認", "이어폰 확인", "Comprobar auriculares"},
	"确认这是耳机":                      {"确认这是耳机", "確認這是耳機", "Confirm headphones", "イヤホンと確認", "이어폰으로 확인", "Confirmar auriculares"},
	"请确认当前输出是耳机，而不是音箱或车载设备。": {"请确认当前输出是耳机，而不是音箱或车载设备。", "請確認目前輸出是耳機，而非音箱或車載裝置。", "Confirm this output is headphones, not a speaker or car.", "スピーカーや車載機器ではなく、イヤホンであることを確認してください。", "스피커나 차량이 아닌 이어폰인지 확인하세요.", "Confirma que son auriculares, no un altavoz ni un coche."},
	"正在准备…":         {"正在准备…", "正在準備…", "Preparing…", "準備中…", "준비 중…", "Preparando…"},
	"本机存储不可用或空间不足。": {"本机存储不可用或空间不足。", "本機儲存無法使用或空間不足。", "Local storage is unavailable or full.", "保存領域を利用できないか、空き容量がありません。", "로컬 저장소를 사용할 수 없거나 공간이 부족합니다.", "El almacenamiento local no está disponible o está lleno."},
	"操作未完成，请重试。":    {"操作未完成，请重试。", "操作未完成，請重試。", "Could not complete the action. Please retry.", "操作を完了できませんでした。もう一度お試しください。", "작업을 완료하지 못했습니다. 다시 시도하세요.", "No se pudo completar la acción. Inténtalo de nuevo."},
	"休息期间关闭窗口会收至托盘，退出应用会停止提醒。": {"休息期间关闭窗口会收至托盘，退出应用会停止提醒。", "休息期間關閉視窗會收至選單列，結束應用程式會停止提醒。", "Closing the window during a rest keeps it in the tray. Quitting stops the alarm.", "休憩中にウィンドウを閉じるとトレイに残ります。アプリを終了すると通知も停止します。", "휴식 중 창을 닫으면 트레이에 유지됩니다. 앱을 종료하면 알림도 중지됩니다.", "Cerrar la ventana mantiene el descanso en la bandeja. Salir detiene la alarma."},
	"文件和记录仅保存在这台设备上。":          {"文件和记录仅保存在这台设备上。", "檔案與記錄僅儲存在此裝置。", "Files and records stay on this device.", "ファイルと記録はこのデバイスにのみ保存されます。", "파일과 기록은 이 기기에만 저장됩니다.", "Los archivos y registros quedan en este dispositivo."},
	"声音已停止，请检查耳机或重新选择声音。":      {"声音已停止，请检查耳机或重新选择声音。", "聲音已停止，請檢查耳機或重新選擇聲音。", "Audio stopped. Check headphones or choose another sound.", "再生を停止しました。イヤホンまたは音源を確認してください。", "재생이 중지되었습니다. 이어폰 또는 음원을 확인하세요.", "El audio se detuvo. Comprueba los auriculares o elige otro sonido."},
}

func translateNative(language string, dictionaries map[string]map[string]string, key string, args ...any) string {
	text := key
	if translated, ok := dictionaries[language][key]; ok {
		text = translated
	}
	if values, ok := desktopCopy[key]; ok {
		index := slices.Index(languageIDs, language)
		if index < 0 {
			index = 2
		}
		text = values[index]
	}
	for _, arg := range args {
		index := strings.IndexAny(text, "%")
		if index < 0 || index+1 >= len(text) {
			break
		}
		if token := text[index : index+2]; token == "%@" || token == "%d" {
			text = text[:index] + fmt.Sprint(arg) + text[index+2:]
		}
	}
	return text
}
