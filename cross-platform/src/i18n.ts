import type { Language } from './core/model';
// Existing product copy comes directly from the untouched Swift localization resources.
// Only platform-specific copy is defined here, in the same six languages.
const newCopy: Record<string, string[]> = {
  '把提醒留给自己': ['把提醒留给自己', '把提醒留給自己', 'A MOMENT FOR YOU', '自分だけのひととき', '나만을 위한 순간', 'UN MOMENTO PARA TI'],
  '片刻安静': ['片刻安静', '片刻安靜', 'Quiet time', '静かな時間', '조용한 시간', 'Un momento de calma'],
  '试听': ['试听', '試聽', 'Preview', '試聴', '미리 듣기', 'Escuchar'],
  '试听唤醒铃声': ['试听唤醒铃声', '試聽喚醒鈴聲', 'Preview alarm', 'アラームを試聴', '알람 미리 듣기', 'Probar alarma'],
  '持续响铃': ['持续响铃', '持續響鈴', 'Keep ringing', '繰り返し鳴らす', '계속 울리기', 'Seguir sonando'],
  '持续响铃，直到手动结束或稍后提醒。': ['持续响铃，直到手动结束或稍后提醒。', '持續響鈴，直到手動結束或稍後提醒。', 'Repeats until you stop or snooze.', '停止またはスヌーズするまで繰り返します。', '중지하거나 미룰 때까지 반복합니다.', 'Se repite hasta detener o posponer.'],
  '关闭时最多提醒 3 分钟。': ['关闭时最多提醒 3 分钟。', '關閉時最多提醒 3 分鐘。', 'Rings for up to 3 minutes when off.', 'オフの場合は最長3分間鳴ります。', '끄면 최대 3분간 울립니다.', 'Si está desactivado, suena hasta 3 minutos.'],
  '唤醒铃声音量': ['唤醒铃声音量', '喚醒鈴聲音量', 'Alarm volume', 'アラーム音量', '알람 음량', 'Volumen de alarma'],
  '稍后提醒': ['稍后提醒', '稍後提醒', 'Snooze', 'スヌーズ', '다시 알림', 'Posponer'],
  '震动': ['震动', '震動', 'Vibration', '振動', '진동', 'Vibración'],
  '结束一次休息后，足迹会出现在这里。': ['结束一次休息后，足迹会出现在这里。', '結束一次休息後，足跡會出現在這裡。', 'Your rests will appear here when you finish.', '休憩を終えると、ここに記録されます。', '휴식을 마치면 기록이 여기에 표시됩니다.', 'Tus descansos aparecerán aquí al terminar.'],
  bluetoothConfirm: ['我确认此蓝牙设备是耳机，不是音箱或车载设备', '我確認此藍牙裝置是耳機，而非音箱或車載裝置', 'This Bluetooth device is headphones, not a speaker or car', 'このBluetooth機器はスピーカーや車載機器ではなくイヤホンです', '이 블루투스 기기는 스피커나 차량이 아닌 이어폰입니다', 'Este dispositivo Bluetooth son auriculares, no un altavoz ni un coche'],
  local: ['仅在这台设备上', '僅在這台裝置上', 'Only on this device', 'このデバイスのみ', '이 기기에만 저장', 'Solo en este dispositivo'],
  seconds: ['秒', '秒', 'sec', '秒', '초', 's'],
  custom: ['自定义', '自訂', 'Custom', 'カスタム', '사용자 설정', 'Personalizado'],
  appearance: ['外观', '外觀', 'Appearance', '外観', '화면 모드', 'Apariencia'],
  light: ['浅色', '淺色', 'Light', 'ライト', '라이트', 'Claro'],
  dark: ['深色', '深色', 'Dark', 'ダーク', '다크', 'Oscuro'],
  largeText: ['大字体', '大字體', 'Larger text', '大きな文字', '큰 글씨', 'Texto grande'],
  output: ['音频输出', '音訊輸出', 'Audio output', '音声出力', '오디오 출력', 'Salida de audio'],
  systemOutput: ['系统默认音频输出', '系統預設音訊輸出', 'System audio output', 'システムの音声出力', '시스템 오디오 출력', 'Salida de audio del sistema'],
  webOutput: ['声音跟随系统当前选择的设备，可能通过扬声器播放。', '聲音跟隨系統目前選擇的裝置，可能透過揚聲器播放。', 'Sound follows the device selected in system settings, including speakers.', 'システムで選択した機器から再生します。スピーカーで再生される場合があります。', '시스템에서 선택한 기기로 재생하며 스피커로 나올 수 있습니다.', 'El sonido usa el dispositivo seleccionado en el sistema, incluidos los altavoces.'],
  '继续休息': ['继续休息', '繼續休息', 'Resume rest', '休憩を再開', '휴식 재개', 'Reanudar descanso'],
  webRestored: ['应用曾关闭，计时未在后台继续。可手动继续休息。', '應用程式曾關閉，計時未在背景繼續。可手動繼續休息。', 'The app was closed. The timer did not continue. Resume your rest manually.', 'アプリが終了し、タイマーは停止しました。手動で休憩を再開してください。', '앱이 종료되어 타이머가 중지되었습니다. 직접 휴식을 재개하세요.', 'La app se cerró y el temporizador se detuvo. Reanuda el descanso manualmente.'],
  checkOutput: ['检查耳机', '檢查耳機', 'Check headphones', 'イヤホンを確認', '이어폰 확인', 'Comprobar auriculares'],
  webLimit: ['Web 版请保持页面打开、设备唤醒；锁屏、后台节流或关闭页面可能导致提醒失效。声音跟随系统输出，可能通过扬声器播放。', 'Web 版請保持頁面開啟、裝置喚醒；鎖定、背景節流或關閉頁面可能導致提醒失效。聲音跟隨系統輸出，可能透過揚聲器播放。', 'Keep this page open and the device awake. Locking, background throttling or closing the page can prevent alarms. Sound follows the system output and may play through speakers.', 'ページを開き端末を起動状態にしてください。ロックやバックグラウンド制限で通知が止まる場合があります。システム出力に従い、スピーカーで再生される場合があります。', '페이지를 열어 두고 기기를 깨워 두세요. 잠금, 백그라운드 제한, 페이지 종료 시 알림이 작동하지 않을 수 있습니다. 시스템 출력에 따라 스피커로 재생될 수 있습니다.', 'Mantén la página abierta y el dispositivo activo. El bloqueo, el segundo plano o cerrar la página pueden impedir la alarma. El sonido sigue la salida del sistema y puede usar altavoces.'],
  nativeLimit: ['连接耳机并用短计时测试。请勿强制退出应用；关机、睡眠、来电和耳机没电可能影响提醒。不要作为重要事项的唯一提醒。', '連接耳機並用短計時測試。請勿強制結束應用程式；關機、睡眠、來電及耳機沒電可能影響提醒。勿作重要事項的唯一提醒。', 'Connect headphones and try a short timer. Do not force quit. Shutdown, sleep, calls or depleted headphones can prevent alarms. Use another reminder for important events.', 'イヤホンを接続し短いタイマーで確認してください。強制終了、電源オフ、スリープ、通話、電池切れで動作しない場合があります。重要な予定には別の通知も用意してください。', '이어폰을 연결하고 짧은 타이머로 테스트하세요. 강제 종료, 전원 끄기, 절전, 통화, 배터리 소진 시 알림이 작동하지 않을 수 있습니다. 중요한 일정에는 다른 알림도 사용하세요.', 'Conecta auriculares y prueba un temporizador corto. No fuerces el cierre. Apagado, suspensión, llamadas o batería agotada pueden impedir la alarma. Usa otro aviso para eventos importantes.'],
  mediaHint: ['文件留在本机。最多 20 个，每个 200 MB、2 小时。Web / Windows 播放媒体中的音轨；安卓会提取支持的视频音轨。自定义闹铃仅使用前 60 秒。', '檔案留在本機。最多 20 個，每個 200 MB、2 小時。Web / Windows 播放媒體音軌；Android 擷取支援的影片音軌。自訂鬧鈴僅使用前 60 秒。', 'Files stay local: 20 files, 200 MB and 2 hours each. Web / Windows play the audio track; Android extracts supported video audio. Custom alarms use the first 60 seconds.', 'ファイルは端末内のみ。20件、各200 MB・2時間まで。Web / Windowsは音声トラックを再生し、Androidは対応動画から抽出します。アラームは最初の60秒です。', '파일은 기기에만 저장됩니다. 최대 20개, 각 200 MB 및 2시간. Web / Windows는 오디오 트랙을 재생하고 Android는 지원되는 동영상 음성을 추출합니다. 알람은 처음 60초를 사용합니다.', 'Archivos locales: 20 archivos, 200 MB y 2 horas cada uno. Web / Windows reproducen la pista de audio; Android extrae audio de vídeos compatibles. Alarmas: primeros 60 segundos.'],
  storageError: ['本机存储不可用或空间不足，请释放空间后重试。', '本機儲存無法使用或空間不足，請釋放空間後重試。', 'Local storage is unavailable or full. Free space and try again.', '保存領域を利用できないか、空き容量がありません。', '로컬 저장소를 사용할 수 없거나 공간이 부족합니다.', 'El almacenamiento local no está disponible o está lleno.'],
  mediaError: ['无法导入：请使用含可播放音轨的音频/视频，检查 200 MB、2 小时和 20 个文件的上限。', '無法匯入：請使用含可播放音軌的音訊/影片，檢查 200 MB、2 小時及 20 個檔案上限。', 'Import failed. Use a supported audio/video with an audio track; limits are 200 MB, 2 hours, 20 files.', '読み込めません。対応音声トラックと制限（200 MB、2時間、20件）をご確認ください。', '가져오기 실패. 지원되는 오디오 트랙과 제한(200 MB, 2시간, 20개)을 확인하세요.', 'Error al importar. Usa audio/vídeo compatible; límites: 200 MB, 2 horas, 20 archivos.'],
  restored: ['应用曾关闭，计时未在后台继续。确认耳机后可手动恢复。', '應用程式曾關閉，計時未在背景繼續。確認耳機後可手動恢復。', 'The app was closed. The timer did not continue. Check headphones and resume manually.', 'アプリが終了しました。イヤホンを確認して手動で再開してください。', '앱이 종료되었습니다. 이어폰을 확인한 후 직접 재개하세요.', 'La app se cerró. Comprueba los auriculares y reanuda manualmente.'],
  routeLost: ['耳机输出已变化，声音已停止。确认耳机后继续。', '耳機輸出已變更，聲音已停止。確認耳機後繼續。', 'The headphone output changed. Audio stopped. Check headphones to resume.', '音声出力が変わり再生を停止しました。イヤホンを確認してください。', '이어폰 출력이 변경되어 소리가 중지되었습니다. 확인 후 재개하세요.', 'La salida cambió y el audio se detuvo. Comprueba los auriculares.'],
  audioError: ['声音无法播放，请检查耳机或重新选择音频后继续。', '聲音無法播放，請檢查耳機或重新選擇音訊後繼續。', 'Audio could not play. Check headphones or select another sound and resume.', '再生できません。イヤホンまたは音源を確認してください。', '재생할 수 없습니다. 이어폰 또는 음원을 확인하세요.', 'No se pudo reproducir. Comprueba auriculares o elige otro sonido.'],
  busy: ['正在准备…', '正在準備…', 'Preparing…', '準備中…', '준비 중…', 'Preparando…'],
  privacy: ['无需账号、无广告、无订阅。配置、音频与最多 365 条记录仅保存在此设备。清除浏览器数据或卸载会删除数据。', '無需帳號、無廣告、無訂閱。設定、音訊與最多 365 筆記錄僅儲存在此裝置。清除瀏覽器資料或解除安裝會刪除資料。', 'No account, ads or subscriptions. Settings, audio and up to 365 records stay on this device. Clearing browser data or uninstalling removes them.', 'アカウント・広告・購読なし。設定、音源、最大365件の記録は端末内のみ。ブラウザデータ削除やアンインストールで消去されます。', '계정, 광고, 구독 없음. 설정, 음원, 최대 365개 기록은 기기에만 저장됩니다. 브라우저 데이터 삭제 또는 앱 제거 시 삭제됩니다.', 'Sin cuenta, anuncios ni suscripciones. Ajustes, audio y hasta 365 registros quedan en el dispositivo. Se eliminan al borrar datos del navegador o desinstalar.'],
  otherTab: ['已有另一个耳憩页面正在运行，请先关闭它再使用此页面。', '已有另一個耳憩頁面正在執行，請先關閉。', 'Another HushNest window is open. Close it before using this one.', '別のHushNestページが開いています。先に閉じてください。', '다른 HushNest 창이 열려 있습니다. 먼저 닫아 주세요.', 'Hay otra ventana de HushNest abierta. Ciérrala primero.'],
  wakeLock: ['无法保持屏幕唤醒，请在系统中关闭自动锁屏。', '無法保持螢幕喚醒，請在系統中關閉自動鎖定。', 'Could not keep the screen awake. Disable automatic sleep in system settings.', '画面を起動状態にできません。自動スリープを無効にしてください。', '화면을 깨워 둘 수 없습니다. 자동 절전을 꺼 주세요.', 'No se pudo mantener activo. Desactiva la suspensión automática.'],
  notification: ['安卓后台休息通过常驻静默通知运行。系统可能要求通知权限。', 'Android 背景休息透過常駐靜默通知執行。系統可能要求通知權限。', 'Android uses a persistent silent notification for background rest. Notification permission may be requested.', 'Androidは常駐の無音通知でバックグラウンド動作します。通知許可が必要な場合があります。', 'Android는 지속적인 무음 알림으로 백그라운드 실행됩니다. 알림 권한이 필요할 수 있습니다.', 'Android usa una notificación silenciosa persistente en segundo plano. Puede solicitar permiso.'],
};
const languages: Language[] = ['zh-Hans', 'zh-Hant', 'en', 'ja', 'ko', 'es'];
export type Translate = (key: string, ...args: (string | number)[]) => string;
export function translator(language: Language, dictionary: Record<string, string>): Translate {
  return (key, ...args) => {
    let index = 0;
    return (newCopy[key]?.[languages.indexOf(language)] ?? dictionary[key] ?? key).replace(/%@|%d/g, () => String(args[index++] ?? ''));
  };
}
