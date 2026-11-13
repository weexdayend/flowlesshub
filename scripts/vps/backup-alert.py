#!/usr/bin/env python3
"""Send sanitized FlowlessHub backup lifecycle notifications to Discord."""

from __future__ import annotations

import argparse
import http.client
import json
import math
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Mapping

CREDENTIAL_NAME = "discord-webhook-url"
CREDENTIAL_MAX_BYTES = 4096
HTTP_TIMEOUT_SECONDS = 5.0
MAX_ATTEMPTS = 3
MAX_RETRY_AFTER_SECONDS = 5.0
TOTAL_BUDGET_SECONDS = 25.0
DISCORD_HOST = "discord.com"
WEBHOOK_PATH = re.compile(r"^/api/webhooks/[0-9]+/[A-Za-z0-9._-]+$")
SAFE_RESULT = re.compile(r"^[a-z0-9_-]{1,40}$")
SAFE_EXIT_CODE = re.compile(r"^(?:exited|killed|dumped|)$")
SAFE_EXIT_STATUS = re.compile(r"^[A-Za-z0-9_.-]{0,40}$")


class AlertDeliveryError(Exception):
    """A sanitized delivery or event-validation failure."""


def validate_webhook_url(value: str) -> str:
    """Accept a Discord HTTPS webhook URL, including the normalized wait=true URL."""
    candidate = value.strip()
    try:
        parsed = urllib.parse.urlsplit(candidate)
        port = parsed.port
    except ValueError as exc:
        raise AlertDeliveryError("invalid_webhook_url") from exc

    if (
        parsed.scheme != "https"
        or parsed.hostname != DISCORD_HOST
        or parsed.username is not None
        or parsed.password is not None
        or port not in (None, 443)
        or parsed.query not in ("", "wait=true")
        or parsed.fragment
        or not WEBHOOK_PATH.fullmatch(parsed.path)
    ):
        raise AlertDeliveryError("invalid_webhook_url")

    return urllib.parse.urlunsplit(("https", DISCORD_HOST, parsed.path, "wait=true", ""))


def read_webhook_credential(credentials_directory: str | None = None) -> str:
    directory = credentials_directory or os.environ.get("CREDENTIALS_DIRECTORY", "")
    if not directory:
        raise AlertDeliveryError("credential_directory_unavailable")

    path = Path(directory) / CREDENTIAL_NAME
    try:
        if path.is_symlink() or not path.is_file():
            raise AlertDeliveryError("credential_file_unavailable")
        if path.stat().st_size > CREDENTIAL_MAX_BYTES:
            raise AlertDeliveryError("credential_file_invalid")
        value = path.read_text(encoding="utf-8").strip()
    except AlertDeliveryError:
        raise
    except (OSError, UnicodeError):
        raise AlertDeliveryError("credential_file_unavailable") from None

    if not value:
        raise AlertDeliveryError("credential_file_empty")
    return validate_webhook_url(value)


class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Do not forward the credential-bearing webhook URL to another host."""

    def redirect_request(self, req: Any, fp: Any, code: int, msg: str, headers: Any, newurl: str) -> None:
        return None


def _retry_after_seconds(headers: Any, body: bytes) -> float | None:
    candidate: Any = headers.get("Retry-After") if headers is not None else None
    if candidate is None:
        try:
            decoded = json.loads(body.decode("utf-8"))
            candidate = decoded.get("retry_after") if isinstance(decoded, dict) else None
        except (UnicodeDecodeError, json.JSONDecodeError):
            return None

    try:
        delay = float(candidate)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(delay) or delay < 0:
        return None
    return delay


def build_discord_payload(embed: Mapping[str, Any]) -> dict[str, Any]:
    """Wrap one validated operational embed in a mention-safe Discord payload."""
    if not isinstance(embed, Mapping):
        raise AlertDeliveryError("message_embed_invalid")

    title = embed.get("title")
    description = embed.get("description")
    fields = embed.get("fields", [])
    if (
        not isinstance(title, str)
        or not title
        or len(title) > 256
        or not isinstance(description, str)
        or len(description) > 4096
        or not isinstance(fields, list)
        or len(fields) > 25
    ):
        raise AlertDeliveryError("message_embed_invalid")

    for field in fields:
        if (
            not isinstance(field, Mapping)
            or not isinstance(field.get("name"), str)
            or not field["name"]
            or len(field["name"]) > 256
            or not isinstance(field.get("value"), str)
            or not field["value"]
            or len(field["value"]) > 1024
        ):
            raise AlertDeliveryError("message_embed_invalid")

    return {
        "username": "FlowlessHub Backup Ops",
        "embeds": [dict(embed)],
        "allowed_mentions": {"parse": []},
    }


def post_message(
    webhook_url: str,
    embed: Mapping[str, Any],
    *,
    opener: Any | None = None,
    sleep_fn: Any = time.sleep,
    monotonic_fn: Any = time.monotonic,
) -> str:
    """Post one embed; retry only an explicit Discord 429 rejection."""
    payload = json.dumps(
        build_discord_payload(embed),
        separators=(",", ":"),
    ).encode("utf-8")

    target = validate_webhook_url(webhook_url)
    client = opener or urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirectHandler())
    deadline = monotonic_fn() + TOTAL_BUDGET_SECONDS

    for attempt in range(1, MAX_ATTEMPTS + 1):
        remaining = deadline - monotonic_fn()
        if remaining <= 0:
            raise AlertDeliveryError("delivery_budget_exhausted")
        request = urllib.request.Request(
            target,
            data=payload,
            headers={
                "Content-Type": "application/json",
                "Accept": "application/json",
                "User-Agent": "FlowlessHubBackupAlert/1.0",
            },
            method="POST",
        )

        try:
            response = client.open(request, timeout=min(HTTP_TIMEOUT_SECONDS, remaining))
        except urllib.error.HTTPError as exc:
            status = exc.code
            try:
                error_body = exc.read(8192)
            except (OSError, http.client.HTTPException):
                error_body = b""
            finally:
                try:
                    exc.close()
                except (OSError, http.client.HTTPException):
                    pass
            if status == 429 and attempt < MAX_ATTEMPTS:
                delay = _retry_after_seconds(exc.headers, error_body)
                if delay is None:
                    raise AlertDeliveryError("rate_limit_without_retry_after") from None
                if delay > MAX_RETRY_AFTER_SECONDS or delay > deadline - monotonic_fn():
                    raise AlertDeliveryError("rate_limit_retry_after_outside_budget") from None
                sleep_fn(delay)
                continue
            raise AlertDeliveryError(f"http_{status}_delivery_not_confirmed") from None
        except (urllib.error.URLError, TimeoutError, OSError, http.client.HTTPException):
            # A POST may have reached Discord before the connection failed. Do not replay it.
            raise AlertDeliveryError("transport_outcome_unknown_no_retry") from None

        try:
            status = response.getcode()
            response_body = response.read(65536)
        except (OSError, TimeoutError, http.client.HTTPException):
            raise AlertDeliveryError("response_read_failed_delivery_unknown") from None
        finally:
            try:
                response.close()
            except (AttributeError, OSError, http.client.HTTPException):
                pass

        if status != 200:
            raise AlertDeliveryError(f"http_{status}_delivery_not_confirmed")
        try:
            document = json.loads(response_body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise AlertDeliveryError("discord_response_invalid_json") from None
        message_id = document.get("id") if isinstance(document, dict) else None
        if not isinstance(message_id, str) or not message_id.isdigit():
            raise AlertDeliveryError("discord_message_id_missing")
        return message_id

    raise AlertDeliveryError("delivery_attempts_exhausted")


def _monitor_values(environment: Mapping[str, str]) -> tuple[str, str, str, str]:
    unit = environment.get("MONITOR_UNIT", "")
    result = environment.get("MONITOR_SERVICE_RESULT", "")
    exit_code = environment.get("MONITOR_EXIT_CODE", "")
    exit_status = environment.get("MONITOR_EXIT_STATUS", "")
    if not unit or not SAFE_RESULT.fullmatch(result) or not SAFE_EXIT_CODE.fullmatch(exit_code):
        raise AlertDeliveryError("systemd_monitor_context_invalid")
    if not SAFE_EXIT_STATUS.fullmatch(exit_status):
        raise AlertDeliveryError("systemd_monitor_context_invalid")
    return unit, result, exit_code, exit_status


def _build_embed(
    *,
    title: str,
    description: str,
    color: int,
    fields: list[tuple[str, str, bool]],
    now_utc: datetime,
) -> dict[str, Any]:
    """Build a compact, structured Discord embed with explicit UTC/WIB timing."""
    return {
        "title": title,
        "description": description,
        "color": color,
        "fields": [
            {"name": name, "value": value, "inline": inline}
            for name, value, inline in fields
        ],
        "footer": {"text": "FLOWLESSHUB • BACKUP OPERATIONS"},
        "timestamp": now_utc.isoformat(timespec="seconds").replace("+00:00", "Z"),
    }


def _time_field(now_utc: datetime) -> str:
    now_wib = now_utc.astimezone(timezone(timedelta(hours=7)))
    return f"{now_wib:%d %b %Y · %H:%M:%S} WIB\n{now_utc:%d %b %Y · %H:%M:%S} UTC"


def build_message(event: str, environment: Mapping[str, str] | None = None) -> dict[str, Any]:
    """Build a sanitized, event-specific Discord embed."""
    env = environment if environment is not None else os.environ
    now_utc = datetime.now(timezone.utc).replace(microsecond=0)
    time_value = _time_field(now_utc)

    if event == "test":
        return _build_embed(
            title="Discord alert channel connected",
            description=(
                "This is a manual webhook delivery test. It verifies the notification path only; "
                "no backup job was started."
            ),
            color=0x5865F2,
            fields=[
                ("STATUS", "DELIVERY TEST", True),
                ("TRIGGER", "Manual systemd test", True),
                ("BACKUP EXECUTION", "Not started", True),
                ("TARGET SERVICE", "flowlesshub-backup.service", False),
                ("TIME", time_value, False),
            ],
            now_utc=now_utc,
        )

    unit, result, exit_code, exit_status = _monitor_values(env)
    if event == "success":
        if unit != "flowlesshub-backup.service" or result != "success" or exit_code != "exited" or exit_status != "0":
            raise AlertDeliveryError("backup_success_event_context_mismatch")
        return _build_embed(
            title="Backup workflow completed",
            description=(
                "The backup orchestrator exited successfully. This confirms the service-level "
                "result only; local backup, off-site upload, and retention details remain stage-specific."
            ),
            color=0x2ECC71,
            fields=[
                ("STATUS", "SUCCESS", True),
                ("SERVICE", unit, True),
                ("SYSTEMD RESULT", result, True),
                ("PROCESS EXIT", f"{exit_code} / {exit_status}", True),
                ("OFF-SITE STATUS", "Not inferred — inspect the backup stage journal.", False),
                ("TIME", time_value, False),
            ],
            now_utc=now_utc,
        )

    if event == "failure":
        if unit != "flowlesshub-backup.service" or result == "success":
            raise AlertDeliveryError("backup_failure_event_context_mismatch")
        return _build_embed(
            title="Backup workflow failed",
            description=(
                "The backup orchestrator did not complete successfully. Check the service journal "
                "to identify the failed stage; this notification does not guess the cause."
            ),
            color=0xE74C3C,
            fields=[
                ("STATUS", "ACTION REQUIRED", True),
                ("SERVICE", unit, True),
                ("SYSTEMD RESULT", result, True),
                ("PROCESS EXIT", f"{exit_code} / {exit_status}", True),
                ("NEXT STEP", "Review: `journalctl -u flowlesshub-backup.service -n 80 --no-pager`", False),
                ("TIME", time_value, False),
            ],
            now_utc=now_utc,
        )

    synthetic = {
        "test-success": ("flowlesshub-alert-test-success.service", "success", "exited", "0"),
        "test-failure": ("flowlesshub-alert-test-failure.service", "exit-code", "exited", "1"),
    }
    if event in synthetic:
        expected_unit, expected_result, expected_code, expected_status = synthetic[event]
        if unit != expected_unit or exit_code != expected_code or exit_status != expected_status:
            raise AlertDeliveryError("synthetic_event_context_mismatch")
        if result != expected_result:
            raise AlertDeliveryError("synthetic_event_context_mismatch")

        is_success = event == "test-success"
        kind = "SUCCESS" if is_success else "FAILURE"
        return _build_embed(
            title=f"Synthetic lifecycle hook · {kind.lower()}",
            description=(
                "This notification confirms the test hook fired. It is a disposable fixture, "
                "not a production backup event; no backup job was started."
            ),
            color=0x2ECC71 if is_success else 0xF1C40F,
            fields=[
                ("TEST RESULT", f"{kind} HOOK", True),
                ("HOOK", "OnSuccess" if is_success else "OnFailure", True),
                ("SOURCE UNIT", unit, False),
                ("SOURCE RESULT", result, True),
                ("SOURCE EXIT", f"{exit_code} / {exit_status}", True),
                ("BACKUP EXECUTION", "Not started", True),
                ("TIME", time_value, False),
            ],
            now_utc=now_utc,
        )

    raise AlertDeliveryError("unsupported_event")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--event",
        required=True,
        choices=("success", "failure", "test", "test-success", "test-failure"),
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        embed = build_message(args.event)
        webhook_url = read_webhook_credential()
        message_id = post_message(webhook_url, embed)
    except AlertDeliveryError as exc:
        print(
            f"ALERT_DELIVERY_RESULT=failure event={args.event} reason={exc}",
            file=sys.stderr,
            flush=True,
        )
        return 1

    print(
        f"ALERT_DELIVERY_RESULT=success event={args.event} http_status=200 message_id={message_id}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
