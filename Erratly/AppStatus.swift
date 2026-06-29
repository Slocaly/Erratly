enum AppStatus {
    case loading, ready, processing, error

    var symbol: String {
        switch self {
        case .loading: return "⏳"
        case .ready: return "✦"
        case .processing: return "⟳"
        case .error: return "⚠️"
        }
    }
}

struct Strings {
    let loading: String
    let ready: String
    let processing: String
    let error: String
    let modelPrefix: String
    let language: String
    let autoDetect: String
    let quit: String

    func label(for status: AppStatus) -> String {
        switch status {
        case .loading: return loading
        case .ready: return ready
        case .processing: return processing
        case .error: return error
        }
    }

    static func forLanguage(_ language: String?) -> Strings {
        switch language {
        case "French":
            return Strings(loading: "Chargement du modèle...", ready: "Erratly est prêt", processing: "Correction en cours...", error: "Impossible de charger le modèle", modelPrefix: "Modèle", language: "Langue", autoDetect: "Détection automatique", quit: "Quitter Erratly")
        case "Spanish":
            return Strings(loading: "Cargando modelo...", ready: "Erratly está listo", processing: "Corrigiendo texto...", error: "Error al cargar el modelo", modelPrefix: "Modelo", language: "Idioma", autoDetect: "Detección automática", quit: "Salir de Erratly")
        case "German":
            return Strings(loading: "Modell wird geladen...", ready: "Erratly ist bereit", processing: "Text wird korrigiert...", error: "Modell konnte nicht geladen werden", modelPrefix: "Modell", language: "Sprache", autoDetect: "Automatisch erkennen", quit: "Erratly beenden")
        case "Italian":
            return Strings(loading: "Caricamento modello...", ready: "Erratly è pronto", processing: "Correzione in corso...", error: "Impossibile caricare il modello", modelPrefix: "Modello", language: "Lingua", autoDetect: "Rilevamento automatico", quit: "Esci da Erratly")
        case "Portuguese":
            return Strings(loading: "Carregando modelo...", ready: "Erratly está pronto", processing: "Corrigindo texto...", error: "Falha ao carregar o modelo", modelPrefix: "Modelo", language: "Idioma", autoDetect: "Detecção automática", quit: "Sair do Erratly")
        case "Dutch":
            return Strings(loading: "Model wordt geladen...", ready: "Erratly is klaar", processing: "Tekst wordt gecorrigeerd...", error: "Laden van model mislukt", modelPrefix: "Model", language: "Taal", autoDetect: "Automatisch detecteren", quit: "Erratly afsluiten")
        case "Polish":
            return Strings(loading: "Ładowanie modelu...", ready: "Erratly jest gotowy", processing: "Korygowanie tekstu...", error: "Nie udało się załadować modelu", modelPrefix: "Model", language: "Język", autoDetect: "Automatyczne wykrywanie", quit: "Zamknij Erratly")
        case "Russian":
            return Strings(loading: "Загрузка модели...", ready: "Erratly готов к работе", processing: "Исправление текста...", error: "Не удалось загрузить модель", modelPrefix: "Модель", language: "Язык", autoDetect: "Автоопределение", quit: "Выйти из Erratly")
        case "Japanese":
            return Strings(loading: "モデルを読み込み中...", ready: "Erratly は使用可能です", processing: "テキストを修正中...", error: "モデルの読み込みに失敗しました", modelPrefix: "モデル", language: "言語", autoDetect: "自動検出", quit: "Erratly を終了")
        case "Chinese":
            return Strings(loading: "正在加载模型...", ready: "Erratly 已就绪", processing: "正在纠正文本...", error: "模型加载失败", modelPrefix: "模型", language: "语言", autoDetect: "自动检测", quit: "退出 Erratly")
        case "Korean":
            return Strings(loading: "모델 로딩 중...", ready: "Erratly 사용 준비 완료", processing: "텍스트 수정 중...", error: "모델 로드 실패", modelPrefix: "모델", language: "언어", autoDetect: "자동 감지", quit: "Erratly 종료")
        case "Arabic":
            return Strings(loading: "جارٍ تحميل النموذج...", ready: "Erratly جاهز للاستخدام", processing: "جارٍ تصحيح النص...", error: "فشل في تحميل النموذج", modelPrefix: "النموذج", language: "اللغة", autoDetect: "الكشف التلقائي", quit: "إنهاء Erratly")
        default:
            return Strings(loading: "Model is downloading...", ready: "Erratly is ready to use", processing: "Correcting text...", error: "Failed to load model", modelPrefix: "Model", language: "Language", autoDetect: "Auto-detect", quit: "Quit Erratly")
        }
    }
}
