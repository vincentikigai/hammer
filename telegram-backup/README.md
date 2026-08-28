# Telegram Backup

Backs up Telegram messages to one JSONL file per chat. The backup is resumable: messages already present in `messages.jsonl` are skipped on later runs. Media is optional.

## Requirements

- Python 3.9 or newer
- Telegram API credentials from <https://my.telegram.org/apps>
- A Telegram account that can access the chats being exported

Install Python from <https://www.python.org/downloads/> and ensure the `python` command is available. Debian-based systems may need `sudo apt install python3 python-is-python3 python3-venv python3-pip`.

## Setup

```text
cd telegram-backup
python -m venv .venv
python -m pip install -r requirements.txt
```

Activate `.venv` using your shell, then set `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` in your environment before running the tool.

Keep the API hash private. The first run asks for the phone number, login code, and 2FA password when needed. The authenticated session is stored in the output directory and should be treated as a secret.

## Usage

Back up all chats:

```text
python telegram_backup.py
```

Back up selected chats by username, numeric ID, or contact name:

```text
python telegram_backup.py --chat example_channel --chat 123456789
```

Include media and restrict a run to the newest 1,000 messages per chat:

```text
python telegram_backup.py --media --limit 1000 --output D:\Backups\Telegram
```

Each chat gets `messages.jsonl`; downloaded media is placed in that chat's `media` folder. JSONL is append-only and UTF-8 encoded, so it can be processed with standard Python tools.
