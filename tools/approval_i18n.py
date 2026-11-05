"""Localized, role-free strings for the security approval surface.

The approval prompt is a security UI, not a chat persona. Every string here is
technical; no character name, role-play, or in-group phrasing is permitted.
"""
from __future__ import annotations

import os

DEFAULT_LANGUAGE = "en"

TRANSLATIONS: dict[str, dict[str, str]] = {
    "en": {
        "header": "Broker evidence — raw parameters, not agent paraphrasing",
        "timeout": "TOTP approval timed out; no action was executed.",
        "approved": "Request approved; no file operation was executed by the Broker.",
        "action": "Action",
        "target": "Target",
        "size": "Size (bytes)",
        "mtime": "Modified",
        "sha256": "SHA-256",
        "old_size": "Old size (bytes)",
        "new_size": "New size (bytes)",
        "source": "Source",
        "diff": "Diff",
        "only_once": "This request only: 6-digit TOTP",
        "request_id": "Request ID",
        "manifest": "Request to send {count} file(s). Enter the TOTP code. Full manifest:",
        "url": "URL",
        "binary": "Binary or oversized file; diff omitted",
        "truncated": "Diff truncated",
        "end": "End of diff",
    },
    "zh": {
        "header": "Broker 证据 — 原始参数，未经 Agent 转述",
        "timeout": "TOTP 审批超时，未执行任何操作。",
        "approved": "请求已批准；Broker 未执行文件操作。",
        "action": "动作",
        "target": "目标",
        "size": "大小（字节）",
        "mtime": "修改时间",
        "sha256": "SHA-256",
        "old_size": "原大小（字节）",
        "new_size": "新大小（字节）",
        "source": "来源",
        "diff": "差异",
        "only_once": "仅本次：6 位 TOTP",
        "request_id": "请求号",
        "manifest": "请求发送 {count} 个文件。请输入 TOTP。完整清单：",
        "url": "URL",
        "binary": "二进制或超大文件，已省略差异",
        "truncated": "差异已截断",
        "end": "差异结束",
    },
    "de": {
        "header": "Broker-Beleg — Rohparameter, nicht vom Agent umformuliert",
        "timeout": "TOTP-Freigabe abgelaufen; keine Aktion ausgeführt.",
        "approved": "Anfrage genehmigt; der Broker hat keine Dateioperation ausgeführt.",
        "action": "Aktion", "target": "Ziel", "size": "Größe (Bytes)",
        "mtime": "Geändert", "sha256": "SHA-256",
        "old_size": "Alte Größe (Bytes)", "new_size": "Neue Größe (Bytes)",
        "source": "Quelle", "diff": "Diff", "only_once": "Nur diese Anfrage: 6-stellige TOTP",
        "request_id": "Anfrage-ID",
        "manifest": "Anfrage zum Senden von {count} Datei(en). TOTP eingeben. Vollständige Liste:",
        "url": "URL", "binary": "Binär- oder Großdatei; Diff ausgelassen",
        "truncated": "Diff gekürzt", "end": "Ende des Diff",
    },
    "es": {
        "header": "Evidencia del Broker — parámetros sin reelaboración del Agent",
        "timeout": "La aprobación TOTP expiró; no se ejecutó ninguna acción.",
        "approved": "Solicitud aprobada; el Broker no ejecutó ninguna operación de archivo.",
        "action": "Acción", "target": "Destino", "size": "Tamaño (bytes)",
        "mtime": "Modificado", "sha256": "SHA-256",
        "old_size": "Tamaño anterior (bytes)", "new_size": "Tamaño nuevo (bytes)",
        "source": "Origen", "diff": "Diferencia", "only_once": "Solo esta solicitud: TOTP de 6 dígitos",
        "request_id": "ID de solicitud",
        "manifest": "Solicitud para enviar {count} archivo(s). Introduzca TOTP. Lista completa:",
        "url": "URL", "binary": "Archivo binario o grande; diferencia omitida",
        "truncated": "Diferencia truncada", "end": "Fin de la diferencia",
    },
    "fr": {
        "header": "Preuve du Broker — paramètres bruts, sans reformulation de l'Agent",
        "timeout": "Approbation TOTP expirée ; aucune action exécutée.",
        "approved": "Demande approuvée ; le Broker n'a exécuté aucune opération de fichier.",
        "action": "Action", "target": "Cible", "size": "Taille (octets)",
        "mtime": "Modifié", "sha256": "SHA-256",
        "old_size": "Ancienne taille (octets)", "new_size": "Nouvelle taille (octets)",
        "source": "Source", "diff": "Diff", "only_once": "Cette demande uniquement : TOTP à 6 chiffres",
        "request_id": "ID de demande",
        "manifest": "Demande d'envoi de {count} fichier(s). Saisissez le TOTP. Liste complète :",
        "url": "URL", "binary": "Fichier binaire ou volumineux ; diff omis",
        "truncated": "Diff tronqué", "end": "Fin du diff",
    },
    "ja": {
        "header": "Broker の証拠 — Agent による言い換えではない生パラメータ",
        "timeout": "TOTP 承認がタイムアウトしました。操作は実行されていません。",
        "approved": "リクエストは承認されました。Broker はファイル操作を実行していません。",
        "action": "操作", "target": "対象", "size": "サイズ（バイト）",
        "mtime": "更新日時", "sha256": "SHA-256",
        "old_size": "変更前サイズ（バイト）", "new_size": "変更後サイズ（バイト）",
        "source": "ソース", "diff": "差分", "only_once": "今回のみ：6 桁の TOTP",
        "request_id": "リクエスト ID",
        "manifest": "{count} 件のファイル送信リクエスト。TOTP を入力してください。完全な一覧：",
        "url": "URL", "binary": "バイナリまたは大容量ファイルのため差分を省略",
        "truncated": "差分は切り詰められました", "end": "差分の終わり",
    },
    "ko": {
        "header": "Broker 증거 — Agent가 바꾸지 않은 원시 매개변수",
        "timeout": "TOTP 승인이 만료되었습니다. 어떤 작업도 실행되지 않았습니다.",
        "approved": "요청이 승인되었습니다. Broker는 파일 작업을 실행하지 않았습니다.",
        "action": "작업", "target": "대상", "size": "크기(바이트)",
        "mtime": "수정 시각", "sha256": "SHA-256",
        "old_size": "이전 크기(바이트)", "new_size": "새 크기(바이트)",
        "source": "출처", "diff": "차이", "only_once": "이번 요청만: 6자리 TOTP",
        "request_id": "요청 ID",
        "manifest": "{count}개 파일 전송 요청입니다. TOTP를 입력하세요. 전체 목록:",
        "url": "URL", "binary": "바이너리 또는 대용량 파일이라 차이를 생략했습니다",
        "truncated": "차이가 잘렸습니다", "end": "차이 끝",
    },
    "ru": {
        "header": "Доказательство Broker — исходные параметры без пересказа Agent",
        "timeout": "Срок подтверждения TOTP истёк; действие не выполнено.",
        "approved": "Запрос одобрен; Broker не выполнял файловую операцию.",
        "action": "Действие", "target": "Цель", "size": "Размер (байт)",
        "mtime": "Изменён", "sha256": "SHA-256",
        "old_size": "Старый размер (байт)", "new_size": "Новый размер (байт)",
        "source": "Источник", "diff": "Разница", "only_once": "Только этот запрос: 6-значный TOTP",
        "request_id": "ID запроса",
        "manifest": "Запрос на отправку {count} файл(ов). Введите TOTP. Полный список:",
        "url": "URL", "binary": "Двоичный или слишком большой файл; разница опущена",
        "truncated": "Разница усечена", "end": "Конец разницы",
    },
}


def language() -> str:
    """Return the configured approval language, failing back to English."""
    value = str(os.environ.get("CBS_APPROVAL_LANGUAGE", DEFAULT_LANGUAGE) or "").strip().lower()
    return value if value in TRANSLATIONS else DEFAULT_LANGUAGE


def t(key: str, **values: object) -> str:
    """Translate one technical approval string."""
    table = TRANSLATIONS.get(language(), TRANSLATIONS[DEFAULT_LANGUAGE])
    text = table.get(key) or TRANSLATIONS[DEFAULT_LANGUAGE].get(key, key)
    try:
        return text.format(**values) if values else text
    except (KeyError, ValueError):
        return text
