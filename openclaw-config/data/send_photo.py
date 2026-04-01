#!/usr/bin/env python3
"""
Send a photo to Telegram via Bot API.

Usage:
    python3 data/send_photo.py data/chart.png
    python3 data/send_photo.py data/chart.png "Revenue up 12% MoM"
    python3 data/send_photo.py data/chart.png "caption" 123456789

If no chat_id is given, sends to all allowed users in openclaw.json.
"""
import http.client
import json
import mimetypes
import os
import sys
import uuid
from pathlib import Path


def get_config():
    """Read openclaw.json from standard locations."""
    for p in [
        Path.home() / ".openclaw" / "openclaw.json",
        Path("/home/node/.openclaw/openclaw.json"),  # Docker
    ]:
        if p.exists():
            with open(p) as f:
                return json.load(f)
    print("ERROR: openclaw.json not found", file=sys.stderr)
    sys.exit(1)


def send_photo(token, chat_id, image_path, caption=None):
    """Send a photo using multipart form upload (stdlib only)."""
    boundary = uuid.uuid4().hex

    with open(image_path, "rb") as f:
        image_data = f.read()

    filename = os.path.basename(image_path)
    content_type = mimetypes.guess_type(filename)[0] or "image/png"

    parts = []

    # chat_id
    parts.append(f"--{boundary}\r\n".encode())
    parts.append(b'Content-Disposition: form-data; name="chat_id"\r\n\r\n')
    parts.append(f"{chat_id}\r\n".encode())

    # photo
    parts.append(f"--{boundary}\r\n".encode())
    parts.append(
        f'Content-Disposition: form-data; name="photo"; filename="{filename}"\r\n'.encode()
    )
    parts.append(f"Content-Type: {content_type}\r\n\r\n".encode())
    parts.append(image_data)
    parts.append(b"\r\n")

    # caption (optional)
    if caption:
        parts.append(f"--{boundary}\r\n".encode())
        parts.append(b'Content-Disposition: form-data; name="caption"\r\n\r\n')
        parts.append(f"{caption}\r\n".encode())

    parts.append(f"--{boundary}--\r\n".encode())

    body = b"".join(parts)

    conn = http.client.HTTPSConnection("api.telegram.org")
    conn.request(
        "POST",
        f"/bot{token}/sendPhoto",
        body,
        {"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    resp = conn.getresponse()
    result = json.loads(resp.read())
    conn.close()

    if result.get("ok"):
        print(f"Photo sent to chat {chat_id}")
    else:
        print(f"ERROR sending to {chat_id}: {result.get('description', 'unknown error')}", file=sys.stderr)


def main():
    if len(sys.argv) < 2:
        print("Usage: send_photo.py <image_path> [caption] [chat_id]", file=sys.stderr)
        sys.exit(1)

    image_path = sys.argv[1]
    caption = sys.argv[2] if len(sys.argv) > 2 else None
    explicit_chat_id = sys.argv[3] if len(sys.argv) > 3 else None

    if not os.path.exists(image_path):
        print(f"ERROR: File not found: {image_path}", file=sys.stderr)
        sys.exit(1)

    config = get_config()
    token = config["channels"]["telegram"]["botToken"]

    if explicit_chat_id:
        chat_ids = [explicit_chat_id]
    else:
        allow_from = config["channels"]["telegram"]["allowFrom"]
        chat_ids = [uid.replace("tg:", "") for uid in allow_from]

    for cid in chat_ids:
        send_photo(token, cid, image_path, caption)


if __name__ == "__main__":
    main()
