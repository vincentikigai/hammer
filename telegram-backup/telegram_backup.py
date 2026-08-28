"""Back up Telegram chat history to JSONL, with optional media downloads."""

import argparse
import asyncio
import getpass
import json
import os
from datetime import datetime, timezone
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(description="Back up Telegram chat history")
    parser.add_argument(
        "--chat",
        action="append",
        help="Chat username, numeric ID, or phone/contact name. Repeat for multiple chats.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("telegram-backups"),
        help="Directory for backup files (default: telegram-backups)",
    )
    parser.add_argument("--media", action="store_true", help="Download message media")
    parser.add_argument(
        "--limit",
        type=int,
        help="Maximum messages per chat; omit to back up the complete history",
    )
    return parser.parse_args()


def load_credentials():
    api_id = os.environ.get("TELEGRAM_API_ID")
    api_hash = os.environ.get("TELEGRAM_API_HASH")
    if not api_id or not api_hash:
        raise RuntimeError(
            "Set TELEGRAM_API_ID and TELEGRAM_API_HASH first. "
            "Get them at https://my.telegram.org/apps."
        )

    try:
        return int(api_id), api_hash
    except ValueError as error:
        raise RuntimeError("TELEGRAM_API_ID must be an integer") from error


def json_value(value):
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    if isinstance(value, (list, tuple)):
        return [json_value(item) for item in value]
    if isinstance(value, dict):
        return {str(key): json_value(item) for key, item in value.items()}
    return str(value)


def message_record(message, media_path=None):
    return {
        "id": message.id,
        "date": json_value(message.date),
        "edit_date": json_value(message.edit_date),
        "sender_id": message.sender_id,
        "text": message.message or "",
        "reply_to_msg_id": getattr(message.reply_to, "reply_to_msg_id", None),
        "views": message.views,
        "forwards": message.forwards,
        "media": str(message.media) if message.media else None,
        "media_path": media_path,
        "exported_at": datetime.now(timezone.utc).isoformat(),
    }


def existing_ids(path):
    if not path.exists():
        return set()

    ids = set()
    with path.open("r", encoding="utf-8") as backup:
        for line in backup:
            try:
                ids.add(json.loads(line)["id"])
            except (KeyError, json.JSONDecodeError):
                continue
    return ids


def safe_name(name):
    cleaned = "".join(character if character.isalnum() or character in "-_" else "_" for character in name)
    return cleaned.strip("_") or "chat"


async def backup_chat(client, chat_ref, output, download_media, limit):
    chat = await client.get_entity(chat_ref)
    title = getattr(chat, "title", None) or getattr(chat, "first_name", None) or str(chat_ref)
    chat_dir = output / safe_name(title)
    chat_dir.mkdir(parents=True, exist_ok=True)
    backup_path = chat_dir / "messages.jsonl"
    media_dir = chat_dir / "media"
    exported_ids = existing_ids(backup_path)
    exported = 0
    skipped = 0

    with backup_path.open("a", encoding="utf-8") as backup:
        async for message in client.iter_messages(chat, limit=limit, reverse=True):
            if message.id in exported_ids:
                skipped += 1
                continue

            media_path = None
            if download_media and message.media:
                media_dir.mkdir(exist_ok=True)
                downloaded = await message.download_media(file=str(media_dir))
                if downloaded:
                    media_path = str(Path(downloaded).relative_to(chat_dir))

            backup.write(json.dumps(message_record(message, media_path), ensure_ascii=True) + "\n")
            backup.flush()
            exported += 1

    print(f"{title}: exported {exported}, skipped {skipped} existing messages -> {backup_path}")


async def run(args):
    try:
        from telethon import TelegramClient
    except ImportError as error:
        raise RuntimeError("Telethon is not installed. Run: python -m pip install -r requirements.txt") from error

    api_id, api_hash = load_credentials()
    output = args.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    session_path = output / "telegram_backup_session"
    client = TelegramClient(str(session_path), api_id, api_hash)

    await client.start(
        phone=lambda: input("Telegram phone number: "),
        password=lambda: getpass.getpass("Telegram 2FA password: "),
    )
    try:
        chats = args.chat or [dialog.entity for dialog in await client.get_dialogs()]
        for chat in chats:
            await backup_chat(client, chat, output, args.media, args.limit)
    finally:
        await client.disconnect()


def main():
    args = parse_args()
    try:
        asyncio.run(run(args))
    except KeyboardInterrupt:
        print("Backup interrupted; rerun the command to continue.")
    except RuntimeError as error:
        raise SystemExit(f"Error: {error}") from error


if __name__ == "__main__":
    main()