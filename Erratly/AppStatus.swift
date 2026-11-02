import Combine

enum AppStatus {
    case loading, ready, processing, error, needsSetup

    var symbol: String {
        switch self {
        case .loading: return "⏳"
        case .ready: return "✦"
        case .processing: return "⟳"
        case .error, .needsSetup: return "⚠️"
        }
    }
}

struct Strings {
    let loading: String
    let ready: String
    let processing: String
    let error: String
    let needsSetup: String
    let modelPrefix: String
    let language: String
    let autoDetect: String
    let reviewBeforeApplying: String
    let clearHistory: String
    let settings: String
    let welcomeGuide: String
    let downloadModel: String
    let deleteModel: String
    let deleteModelTitle: String
    let deleteModelMessage: String
    let delete: String
    let cancel: String
    let quit: String

    func label(for status: AppStatus) -> String {
        switch status {
        case .loading: return loading
        case .ready: return ready
        case .processing: return processing
        case .error: return error
        case .needsSetup: return needsSetup
        }
    }

    static func forLanguage(_ language: String?) -> Strings {
        switch language {
        case "French":
            return Strings(loading: "Chargement du modèle...", ready: "Erratly est prêt", processing: "Correction en cours...", error: "Impossible de charger le modèle", needsSetup: "Terminez la configuration d'Erratly", modelPrefix: "Modèle", language: "Langue", autoDetect: "Détection automatique", reviewBeforeApplying: "Vérifier avant d'appliquer", clearHistory: "Effacer l'historique", settings: "Réglages…", welcomeGuide: "Guide de bienvenue…", downloadModel: "Télécharger le modèle", deleteModel: "Supprimer le modèle téléchargé…", deleteModelTitle: "Supprimer le modèle téléchargé ?", deleteModelMessage: "Le modèle sera supprimé de ce Mac. Il faudra le télécharger à nouveau pour utiliser le moteur local.", delete: "Supprimer", cancel: "Annuler", quit: "Quitter Erratly")
        case "Spanish":
            return Strings(loading: "Cargando modelo...", ready: "Erratly está listo", processing: "Corrigiendo texto...", error: "Error al cargar el modelo", needsSetup: "Termina de configurar Erratly", modelPrefix: "Modelo", language: "Idioma", autoDetect: "Detección automática", reviewBeforeApplying: "Revisar antes de aplicar", clearHistory: "Borrar historial", settings: "Ajustes…", welcomeGuide: "Guía de bienvenida…", downloadModel: "Descargar modelo", deleteModel: "Eliminar modelo descargado…", deleteModelTitle: "¿Eliminar el modelo descargado?", deleteModelMessage: "El modelo se eliminará de este Mac. Tendrás que descargarlo de nuevo para usar el motor local.", delete: "Eliminar", cancel: "Cancelar", quit: "Salir de Erratly")
        case "German":
            return Strings(loading: "Modell wird geladen...", ready: "Erratly ist bereit", processing: "Text wird korrigiert...", error: "Modell konnte nicht geladen werden", needsSetup: "Einrichtung von Erratly abschließen", modelPrefix: "Modell", language: "Sprache", autoDetect: "Automatisch erkennen", reviewBeforeApplying: "Vor dem Anwenden überprüfen", clearHistory: "Verlauf löschen", settings: "Einstellungen…", welcomeGuide: "Willkommensanleitung…", downloadModel: "Modell herunterladen", deleteModel: "Heruntergeladenes Modell löschen…", deleteModelTitle: "Heruntergeladenes Modell löschen?", deleteModelMessage: "Das Modell wird von diesem Mac entfernt. Für die lokale Engine muss es erneut heruntergeladen werden.", delete: "Löschen", cancel: "Abbrechen", quit: "Erratly beenden")
        case "Italian":
            return Strings(loading: "Caricamento modello...", ready: "Erratly è pronto", processing: "Correzione in corso...", error: "Impossibile caricare il modello", needsSetup: "Completa la configurazione di Erratly", modelPrefix: "Modello", language: "Lingua", autoDetect: "Rilevamento automatico", reviewBeforeApplying: "Rivedi prima di applicare", clearHistory: "Cancella cronologia", settings: "Impostazioni…", welcomeGuide: "Guida di benvenuto…", downloadModel: "Scarica modello", deleteModel: "Elimina modello scaricato…", deleteModelTitle: "Eliminare il modello scaricato?", deleteModelMessage: "Il modello verrà rimosso da questo Mac. Dovrai scaricarlo di nuovo per usare il motore locale.", delete: "Elimina", cancel: "Annulla", quit: "Esci da Erratly")
        case "Portuguese":
            return Strings(loading: "Carregando modelo...", ready: "Erratly está pronto", processing: "Corrigindo texto...", error: "Falha ao carregar o modelo", needsSetup: "Conclua a configuração do Erratly", modelPrefix: "Modelo", language: "Idioma", autoDetect: "Detecção automática", reviewBeforeApplying: "Revisar antes de aplicar", clearHistory: "Limpar histórico", settings: "Configurações…", welcomeGuide: "Guia de boas-vindas…", downloadModel: "Baixar modelo", deleteModel: "Excluir modelo baixado…", deleteModelTitle: "Excluir o modelo baixado?", deleteModelMessage: "O modelo será removido deste Mac. Será preciso baixá-lo novamente para usar o mecanismo local.", delete: "Excluir", cancel: "Cancelar", quit: "Sair do Erratly")
        case "Dutch":
            return Strings(loading: "Model wordt geladen...", ready: "Erratly is klaar", processing: "Tekst wordt gecorrigeerd...", error: "Laden van model mislukt", needsSetup: "Voltooi de installatie van Erratly", modelPrefix: "Model", language: "Taal", autoDetect: "Automatisch detecteren", reviewBeforeApplying: "Bekijk voor het toepassen", clearHistory: "Geschiedenis wissen", settings: "Instellingen…", welcomeGuide: "Welkomstgids…", downloadModel: "Model downloaden", deleteModel: "Gedownload model verwijderen…", deleteModelTitle: "Gedownload model verwijderen?", deleteModelMessage: "Het model wordt van deze Mac verwijderd. Je moet het opnieuw downloaden om de lokale engine te gebruiken.", delete: "Verwijderen", cancel: "Annuleren", quit: "Erratly afsluiten")
        case "Polish":
            return Strings(loading: "Ładowanie modelu...", ready: "Erratly jest gotowy", processing: "Korygowanie tekstu...", error: "Nie udało się załadować modelu", needsSetup: "Dokończ konfigurację Erratly", modelPrefix: "Model", language: "Język", autoDetect: "Automatyczne wykrywanie", reviewBeforeApplying: "Sprawdź przed zastosowaniem", clearHistory: "Wyczyść historię", settings: "Ustawienia…", welcomeGuide: "Przewodnik powitalny…", downloadModel: "Pobierz model", deleteModel: "Usuń pobrany model…", deleteModelTitle: "Usunąć pobrany model?", deleteModelMessage: "Model zostanie usunięty z tego Maca. Aby używać lokalnego silnika, trzeba będzie pobrać go ponownie.", delete: "Usuń", cancel: "Anuluj", quit: "Zamknij Erratly")
        case "Russian":
            return Strings(loading: "Загрузка модели...", ready: "Erratly готов к работе", processing: "Исправление текста...", error: "Не удалось загрузить модель", needsSetup: "Завершите настройку Erratly", modelPrefix: "Модель", language: "Язык", autoDetect: "Автоопределение", reviewBeforeApplying: "Просмотреть перед применением", clearHistory: "Очистить историю", settings: "Настройки…", welcomeGuide: "Руководство по началу работы…", downloadModel: "Скачать модель", deleteModel: "Удалить загруженную модель…", deleteModelTitle: "Удалить загруженную модель?", deleteModelMessage: "Модель будет удалена с этого Mac. Чтобы пользоваться локальным движком, её придётся скачать снова.", delete: "Удалить", cancel: "Отмена", quit: "Выйти из Erratly")
        case "Japanese":
            return Strings(loading: "モデルを読み込み中...", ready: "Erratly は使用可能です", processing: "テキストを修正中...", error: "モデルの読み込みに失敗しました", needsSetup: "Erratly の設定を完了してください", modelPrefix: "モデル", language: "言語", autoDetect: "自動検出", reviewBeforeApplying: "適用前に確認", clearHistory: "履歴を消去", settings: "設定…", welcomeGuide: "ようこそガイド…", downloadModel: "モデルをダウンロード", deleteModel: "ダウンロードしたモデルを削除…", deleteModelTitle: "ダウンロードしたモデルを削除しますか？", deleteModelMessage: "モデルはこの Mac から削除されます。ローカルエンジンを使うには再度ダウンロードが必要です。", delete: "削除", cancel: "キャンセル", quit: "Erratly を終了")
        case "Chinese":
            return Strings(loading: "正在加载模型...", ready: "Erratly 已就绪", processing: "正在纠正文本...", error: "模型加载失败", needsSetup: "请完成 Erratly 设置", modelPrefix: "模型", language: "语言", autoDetect: "自动检测", reviewBeforeApplying: "应用前预览", clearHistory: "清除历史", settings: "设置…", welcomeGuide: "欢迎指南…", downloadModel: "下载模型", deleteModel: "删除已下载的模型…", deleteModelTitle: "删除已下载的模型？", deleteModelMessage: "模型将从这台 Mac 上移除。要使用本地引擎，需要重新下载。", delete: "删除", cancel: "取消", quit: "退出 Erratly")
        case "Korean":
            return Strings(loading: "모델 로딩 중...", ready: "Erratly 사용 준비 완료", processing: "텍스트 수정 중...", error: "모델 로드 실패", needsSetup: "Erratly 설정을 완료하세요", modelPrefix: "모델", language: "언어", autoDetect: "자동 감지", reviewBeforeApplying: "적용 전 검토", clearHistory: "기록 지우기", settings: "설정…", welcomeGuide: "시작 가이드…", downloadModel: "모델 다운로드", deleteModel: "다운로드한 모델 삭제…", deleteModelTitle: "다운로드한 모델을 삭제할까요?", deleteModelMessage: "모델이 이 Mac에서 제거됩니다. 로컬 엔진을 사용하려면 다시 다운로드해야 합니다.", delete: "삭제", cancel: "취소", quit: "Erratly 종료")
        case "Arabic":
            return Strings(loading: "جارٍ تحميل النموذج...", ready: "Erratly جاهز للاستخدام", processing: "جارٍ تصحيح النص...", error: "فشل في تحميل النموذج", needsSetup: "أكمل إعداد Erratly", modelPrefix: "النموذج", language: "اللغة", autoDetect: "الكشف التلقائي", reviewBeforeApplying: "مراجعة قبل التطبيق", clearHistory: "مسح السجل", settings: "الإعدادات…", welcomeGuide: "دليل الترحيب…", downloadModel: "تنزيل النموذج", deleteModel: "حذف النموذج المُنزَّل…", deleteModelTitle: "حذف النموذج المُنزَّل؟", deleteModelMessage: "سيُزال النموذج من هذا الماك. ستحتاج إلى تنزيله مرة أخرى لاستخدام المحرك المحلي.", delete: "حذف", cancel: "إلغاء", quit: "إنهاء Erratly")
        default:
            return Strings(loading: "Model is downloading...", ready: "Erratly is ready to use", processing: "Correcting text...", error: "Failed to load model", needsSetup: "Finish setting up Erratly", modelPrefix: "Model", language: "Language", autoDetect: "Auto-detect", reviewBeforeApplying: "Review before applying", clearHistory: "Clear correction history", settings: "Settings…", welcomeGuide: "Welcome Guide…", downloadModel: "Download model", deleteModel: "Delete downloaded model…", deleteModelTitle: "Delete the downloaded model?", deleteModelMessage: "The model will be removed from this Mac. You'll need to download it again to use the local engine.", delete: "Delete", cancel: "Cancel", quit: "Quit Erratly")
        }
    }
}

/// Observable mirror of the backend state, for SwiftUI views such as the
/// onboarding window.
final class BackendState: ObservableObject {
    @Published var status: AppStatus = .loading
    /// Fraction of the local model download/load, 0...1.
    @Published var progress: Double = 0
    /// Bumped whenever a correction is written into one of Erratly's own
    /// text fields, so the onboarding practice step can react to it.
    @Published var inAppCorrections = 0
}
