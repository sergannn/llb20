#!/usr/bin/env python3
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


API_BASE = "https://llb.panfilius.ru/llb-api/"
WEB_APP_BASE = "https://llb.panfilius.ru/flutter_app/"
WEB_OPEN_BASE = "https://llb.panfilius.ru/open/tournament/"
STATE_PATH = Path.home() / ".config" / "llb_bot" / "poll_state.json"
CONVERSATION_PATH = Path.home() / ".config" / "llb_bot" / "conversations.json"


def load_env_file() -> None:
    env_path = Path.home() / ".config" / "llb_bot" / "bot.env"
    if not env_path.exists():
        return
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def api_url(method: str) -> str:
    return f"https://api.telegram.org/bot{os.environ['TELEGRAM_BOT_TOKEN']}/{method}"


def request_json(url: str, payload: dict | None = None, timeout: int = 25) -> dict:
    data = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode()
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def send_message(chat_id: int, text: str, reply_markup: dict | None = None) -> None:
    payload = {
        "chat_id": chat_id,
        "text": text,
        "disable_web_page_preview": True,
    }
    if reply_markup is not None:
        payload["reply_markup"] = reply_markup
    request_json(
        api_url("sendMessage"),
        payload,
        timeout=15,
    )


def answer_callback_query(callback_query_id: str, text: str = "") -> None:
    payload = {"callback_query_id": callback_query_id}
    if text:
        payload["text"] = text
    request_json(api_url("answerCallbackQuery"), payload, timeout=15)


def app_tournament_url(tournament_id: int | str) -> str:
    return f"{WEB_OPEN_BASE}?id={tournament_id}"


def tournament_keyboard(tournament_id: int | str) -> dict:
    return {
        "inline_keyboard": [
            [
                {
                    "text": "Открыть турнир",
                    "url": app_tournament_url(tournament_id),
                }
            ],
            [
                {
                    "text": "Записаться",
                    "url": app_tournament_url(tournament_id),
                }
            ],
        ]
    }


def linked_user(telegram_id: int) -> dict | None:
    if telegram_id <= 0:
        return None
    url = API_BASE + "?" + urllib.parse.urlencode(
        {"resource": "telegram_me", "telegram_id": telegram_id}
    )
    data = request_json(url, timeout=15)
    if not data.get("linked"):
        return None
    user = data.get("user")
    return user if isinstance(user, dict) else None


def linked_user_label(user: dict | None) -> str:
    if not user:
        return ""
    display = str(user.get("display_name") or user.get("username") or "").strip()
    username = str(user.get("username") or "").strip()
    if display and username and display != username:
        return f"{display} ({username})"
    return display or username


def created_by_label(telegram_id: int) -> str:
    user = linked_user(telegram_id)
    if user:
        return f"app:{user.get('id')}:{user.get('username')}"
    return f"telegram:{telegram_id}"


def start_login_link(sender: dict, chat_id: int) -> tuple[str, dict | None]:
    telegram_id = int(sender.get("id") or 0)
    if telegram_id <= 0:
        return "Не удалось определить Telegram-пользователя.", None
    data = request_json(
        API_BASE + "?resource=telegram_link_start",
        {
            "telegram_id": telegram_id,
            "telegram_username": sender.get("username") or "",
            "first_name": sender.get("first_name") or "",
            "last_name": sender.get("last_name") or "",
            "chat_id": chat_id,
        },
        timeout=20,
    )
    if not data.get("ok"):
        return "Не удалось создать ссылку привязки.", None
    link_url = str(data.get("link_url") or "")
    return (
        "Откройте приложение по кнопке и войдите или зарегистрируйтесь. "
        "После входа Telegram будет привязан к аккаунту приложения.",
        {"inline_keyboard": [[{"text": "Привязать аккаунт", "url": link_url}]]},
    )


def help_text() -> str:
    return "\n".join(
        [
            "Лига бильярдистов",
            "",
            "/tournaments - ближайшие турниры",
            "/create - создать турнир по шагам",
            "/login - привязать аккаунт приложения",
            "/whoami - проверить привязку",
        ]
    )


def upcoming_items() -> list[dict]:
    url = API_BASE + "?resource=tournaments&status=upcoming&limit=8"
    data = request_json(url, timeout=20)
    return data.get("items") or []


def upcoming_text(items: list[dict]) -> str:
    if not items:
        return "Ближайших турниров пока нет."
    lines = ["Ближайшие турниры:"]
    for item in items:
        date = str(item.get("date_text") or "").replace("\n", " ")
        club = str(item.get("club") or "").strip()
        club_suffix = f" · {club}" if club else ""
        lines.append(
            f"{item.get('id')}. {item.get('title')}\n"
            f"{date}{club_suffix}\n"
            f"{app_tournament_url(item.get('id'))}"
        )
    return "\n\n".join(lines)


def send_upcoming(chat_id: int) -> None:
    items = upcoming_items()
    if not items:
        send_message(chat_id, "Ближайших турниров пока нет.")
        return
    send_message(chat_id, upcoming_text(items))
    for item in items[:5]:
        date = str(item.get("date_text") or "").replace("\n", " ")
        club = str(item.get("club") or "").strip()
        text = f"{item.get('title')}\n{date}"
        if club:
            text += f"\n{club}"
        send_message(chat_id, text, reply_markup=tournament_keyboard(item.get("id")))


def create_tournament(text: str, user_id: int) -> str:
    payload = text.split(maxsplit=1)
    if len(payload) < 2:
        return start_create_flow(user_id)
    parts = [part.strip() for part in payload[1].split("|")]
    if len(parts) < 5:
        return "Формат: Название | Город | Клуб | 25.07.26 19:00 | Пул | 32"
    capacity = 32
    if len(parts) > 5:
        try:
            capacity = int(parts[5])
        except ValueError:
            capacity = 32
    data = request_json(
        API_BASE + "?resource=tournament_create",
        {
            "title": parts[0],
            "city": parts[1],
            "club": parts[2],
            "date_text": parts[3],
            "discipline": parts[4],
            "participants_limit": capacity,
            "tournament_type": "single elimination",
            "created_by": created_by_label(user_id),
        },
        timeout=35,
    )
    item = data.get("item") or {}
    if not data.get("ok") or not item:
        return "Не удалось создать турнир. Проверьте формат команды."
    return (
        f"Турнир создан: {item.get('title')}\n"
        f"{app_tournament_url(item.get('id'))}"
    )


def join_tournament(text: str, user_id: int, fallback_name: str) -> str:
    payload = text.split(maxsplit=2)
    if len(payload) < 2 or not payload[1].isdigit():
        return "Запись делается из карточки турнира после входа в приложение."
    name = payload[2].strip() if len(payload) > 2 else fallback_name
    if not name:
        name = f"Telegram user {user_id}"
    data = request_json(
        API_BASE + "?resource=tournament_registration",
        {
            "tournament_id": int(payload[1]),
            "action": "register",
            "username": f"telegram:{user_id}",
            "name": name,
        },
        timeout=25,
    )
    if not data.get("ok"):
        return "Не удалось записаться. Возможно, этот турнир не создан в приложении."
    return f"Запись сохранена: {name}"


def load_conversations() -> dict:
    try:
        return json.loads(CONVERSATION_PATH.read_text())
    except Exception:
        return {}


def save_conversations(data: dict) -> None:
    CONVERSATION_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONVERSATION_PATH.write_text(json.dumps(data, ensure_ascii=False))


def start_create_flow(user_id: int) -> str:
    conversations = load_conversations()
    conversations[str(user_id)] = {"mode": "create", "step": "title", "data": {}}
    save_conversations(conversations)
    return "Создаем турнир. Напишите название турнира."


def handle_create_flow(user_id: int, text: str) -> str | None:
    conversations = load_conversations()
    state = conversations.get(str(user_id))
    if not state or state.get("mode") != "create":
        return None
    if text.lower() in {"/cancel", "отмена"}:
        conversations.pop(str(user_id), None)
        save_conversations(conversations)
        return "Создание турнира отменено."

    data = state.setdefault("data", {})
    step = state.get("step")
    if step == "title":
        data["title"] = text.strip()
        state["step"] = "city"
        reply = "Город?"
    elif step == "city":
        data["city"] = text.strip()
        state["step"] = "club"
        reply = "Клуб?"
    elif step == "club":
        data["club"] = text.strip()
        state["step"] = "date_text"
        reply = "Дата и время? Например: 25.07.26 19:00"
    elif step == "date_text":
        data["date_text"] = text.strip()
        state["step"] = "discipline"
        reply = "Дисциплина? Например: Пул или Пирамида"
    elif step == "discipline":
        data["discipline"] = text.strip()
        state["step"] = "capacity"
        reply = "Сколько участников? Например: 32"
    elif step == "capacity":
        data["capacity"] = int(text.strip()) if text.strip().isdigit() else 32
        conversations.pop(str(user_id), None)
        save_conversations(conversations)
        result = request_json(
            API_BASE + "?resource=tournament_create",
            {
                "title": data.get("title", ""),
                "city": data.get("city", ""),
                "club": data.get("club", ""),
                "date_text": data.get("date_text", ""),
                "discipline": data.get("discipline", "Пирамида"),
                "participants_limit": data.get("capacity", 32),
                "tournament_type": "single elimination",
                "created_by": created_by_label(user_id),
            },
            timeout=35,
        )
        item = result.get("item") or {}
        if not result.get("ok") or not item:
            return "Не удалось создать турнир. Попробуйте еще раз через /create."
        return (
            f"Турнир создан: {item.get('title')}\n"
            f"{app_tournament_url(item.get('id'))}"
        )
    else:
        conversations.pop(str(user_id), None)
        reply = start_create_flow(user_id)
    save_conversations(conversations)
    return reply


def load_offset() -> int | None:
    try:
        return int(json.loads(STATE_PATH.read_text()).get("offset"))
    except Exception:
        return None


def save_offset(offset: int) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps({"offset": offset}))


def handle_update(update: dict) -> None:
    if update.get("callback_query"):
        callback = update["callback_query"]
        callback_id = str(callback.get("id") or "")
        data = str(callback.get("data") or "")
        answer_callback_query(callback_id)
        message = callback.get("message") or {}
        chat = message.get("chat") or {}
        chat_id = int(chat.get("id") or 0)
        if chat_id and data.startswith("join:"):
            tournament_id = data.split(":", 1)[1]
            send_message(
                chat_id,
                "Чтобы записаться, откройте турнир и войдите в аккаунт.",
                reply_markup=tournament_keyboard(tournament_id),
            )
        return

    message = update.get("message") or {}
    chat = message.get("chat") or {}
    sender = message.get("from") or {}
    chat_id = int(chat.get("id") or 0)
    if chat_id == 0:
        return
    text = str(message.get("text") or "").strip()
    user_id = int(sender.get("id") or 0)
    name = " ".join(
        part for part in [sender.get("first_name"), sender.get("last_name")] if part
    ).strip()
    command = text.split(maxsplit=1)[0].split("@", 1)[0].lower() if text else ""
    try:
        flow_reply = None if command.startswith("/") else handle_create_flow(user_id, text)
        if flow_reply is not None:
            reply = flow_reply
        elif command == "/tournaments":
            send_upcoming(chat_id)
            return
        elif command == "/create":
            reply = create_tournament(text, user_id)
        elif command == "/join":
            reply = join_tournament(text, user_id, name)
        elif command == "/login":
            reply, keyboard = start_login_link(sender, chat_id)
            send_message(chat_id, reply, reply_markup=keyboard)
            return
        elif command == "/whoami":
            user = linked_user(user_id)
            reply = (
                f"Telegram привязан к аккаунту: {linked_user_label(user)}"
                if user
                else "Telegram пока не привязан. Нажмите /login."
            )
        else:
            user = linked_user(user_id)
            label = linked_user_label(user)
            reply = (f"Вы вошли как {label}\n\n" if label else "") + help_text()
    except Exception as exc:
        reply = f"Не получилось выполнить команду: {exc}"
    send_message(chat_id, reply)


def main() -> None:
    load_env_file()
    if "TELEGRAM_BOT_TOKEN" not in os.environ:
        raise SystemExit("TELEGRAM_BOT_TOKEN is not set")
    offset = load_offset()
    while True:
        params = {"timeout": 25, "allowed_updates": ["message", "callback_query"]}
        if offset is not None:
            params["offset"] = offset
        url = api_url("getUpdates") + "?" + urllib.parse.urlencode(params, doseq=True)
        try:
            data = request_json(url, timeout=35)
            for update in data.get("result") or []:
                offset = int(update["update_id"]) + 1
                save_offset(offset)
                handle_update(update)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            print(f"poll error: {exc}", flush=True)
            time.sleep(5)


if __name__ == "__main__":
    main()
