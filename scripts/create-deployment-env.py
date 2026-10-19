#!/usr/bin/env python3
import base64
import getpass
import os
import re
import secrets
import subprocess
import sys
from pathlib import Path


def normalize_domain(value: str) -> str:
    try:
        domain = value.strip().rstrip(".").encode("idna").decode("ascii").lower()
    except UnicodeError as error:
        raise ValueError("Enter a valid DNS hostname.") from error

    labels = domain.split(".")
    if (
        len(domain) > 253
        or len(labels) < 2
        or any(
            len(label) > 63
            or re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?", label) is None
            for label in labels
        )
    ):
        raise ValueError("Enter a valid DNS hostname.")

    return domain


def deployment_values(
    environment: str,
    domain: str,
    app_image_tag: str,
    client_id: str,
    client_secret: str,
) -> str:
    database = f"control_center_{environment}"
    database_user = f"control_center_{environment}"
    password = secrets.token_hex(32)
    encryption_key = base64.urlsafe_b64encode(secrets.token_bytes(32)).decode("ascii").rstrip("=")
    webhook_secret = secrets.token_hex(32)

    return "\n".join(
        [
            "NODE_ENV=production",
            f"APP_IMAGE_TAG={app_image_tag}",
            f"APP_DOMAIN={domain}",
            f"APP_ORIGIN=https://{domain}",
            f"PUBLIC_API_URL=https://{domain}",
            "PORT=3000",
            "HOST=0.0.0.0",
            f"APP_PROXY_ALIAS=control-center-{environment}-api",
            f"APP_EDGE_NETWORK=ccc-{environment}-edge",
            f"POSTGRES_DB={database}",
            f"POSTGRES_USER={database_user}",
            f"POSTGRES_PASSWORD={password}",
            f"DATABASE_URL=postgresql://{database_user}:{password}@database:5432/{database}?schema=public",
            f"GITHUB_CLIENT_ID={client_id}",
            f"GITHUB_CLIENT_SECRET={client_secret}",
            f"GITHUB_WEBHOOK_SECRET={webhook_secret}",
            f"APP_ENCRYPTION_KEY={encryption_key}",
            "FCM_PROJECT_ID=",
            "",
        ]
    )


def create_environment_files(
    root: Path,
    staging_domain: str,
    production_domain: str,
    app_image_tag: str,
    staging_oauth: tuple[str, str],
    production_oauth: tuple[str, str],
) -> None:
    files = {
        ".env.staging": deployment_values("staging", staging_domain, app_image_tag, *staging_oauth),
        ".env.production": deployment_values("production", production_domain, app_image_tag, *production_oauth),
        ".env.proxy": (
            f"STAGING_DOMAIN={staging_domain}\n"
            f"PRODUCTION_DOMAIN={production_domain}\n"
            "CADDYFILE=./Caddyfile\n"
        ),
    }
    created: list[Path] = []

    try:
        for filename, contents in files.items():
            path = root / filename
            descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            created.append(path)
            with os.fdopen(descriptor, "w", encoding="utf-8") as output:
                output.write(contents)
    except OSError as error:
        cleanup_errors: list[str] = []
        for path in created:
            try:
                path.unlink(missing_ok=True)
            except OSError:
                cleanup_errors.append(path.name)
        if cleanup_errors:
            raise RuntimeError(
                f"Environment file creation failed; inspect partial files: {', '.join(cleanup_errors)}."
            ) from error
        raise RuntimeError("Environment file creation failed; newly created partial files were removed.") from error


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print("Run this command in a protected interactive terminal.", file=sys.stderr)
        return 2

    filenames = (".env.staging", ".env.production", ".env.proxy")
    existing = [filename for filename in filenames if (root / filename).exists()]
    if existing:
        print(
            f"Refusing to overwrite existing environment files: {', '.join(existing)}. "
            "Back them up and review them manually first.",
            file=sys.stderr,
        )
        return 1

    try:
        status = subprocess.run(
            ["git", "-C", str(root), "status", "--porcelain"],
            check=True,
            capture_output=True,
            text=True,
        )
        if status.stdout.strip():
            print("Commit deployment changes before generating environment files.", file=sys.stderr)
            return 1

        commit = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

        staging_domain = normalize_domain(input("Staging domain: "))
        production_domain = normalize_domain(input("Production domain: "))
        if staging_domain == production_domain:
            print("Staging and production domains must be different.", file=sys.stderr)
            return 1

        staging_client_id = getpass.getpass("Staging OAuth App Client ID (hidden): ").strip()
        staging_client_secret = getpass.getpass("Staging OAuth App Client Secret (hidden): ").strip()
        production_client_id = getpass.getpass("Production OAuth App Client ID (hidden): ").strip()
        production_client_secret = getpass.getpass("Production OAuth App Client Secret (hidden): ").strip()
        credentials = (staging_client_id, staging_client_secret, production_client_id, production_client_secret)
        if any(not value for value in credentials):
            print("All four OAuth App credential fields are required.", file=sys.stderr)
            return 1
        if staging_client_id == production_client_id or staging_client_secret == production_client_secret:
            print("Use separate OAuth Apps and credentials for staging and production.", file=sys.stderr)
            return 1

        create_environment_files(
            root,
            staging_domain,
            production_domain,
            commit,
            (staging_client_id, staging_client_secret),
            (production_client_id, production_client_secret),
        )
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        return 1
    except ValueError:
        print("Environment files were not created; check the domain input.", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError:
        print("Environment files were not created; check repository metadata.", file=sys.stderr)
        return 1
    except OSError:
        print("Environment files were not created; check filesystem permissions.", file=sys.stderr)
        return 1

    print("Created .env.staging, .env.production, and .env.proxy with mode 0600.")
    print("Generated independent database, encryption, and webhook secrets without displaying them.")
    print("No containers or system services were started.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
