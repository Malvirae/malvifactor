import argparse
import asyncio
import sys

from sqlalchemy import select

from app.core.database import AsyncSessionLocal, Base, engine
from app.core.security import hash_password
from app.models.user import User, UserProfile
from app.services.ciqual_importer import import_ciqual


async def _ensure_schema() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def _create_user(
    email: str,
    username: str,
    display_name: str,
    password: str,
) -> int:
    await _ensure_schema()
    normalized_email = email.strip().lower()
    normalized_username = username.strip()

    async with AsyncSessionLocal() as session:
        existing = await session.execute(
            select(User).where(
                (User.email == normalized_email)
                | (User.username == normalized_username)
            )
        )
        if existing.scalar_one_or_none() is not None:
            print(
                f"Error: user with email '{normalized_email}' or username "
                f"'{normalized_username}' already exists.",
                file=sys.stderr,
            )
            return 1

        user = User(
            email=normalized_email,
            username=normalized_username,
            display_name=display_name.strip(),
            hashed_password=hash_password(password),
            is_active=True,
        )
        user.profile = UserProfile()
        session.add(user)
        await session.commit()
        await session.refresh(user)
        print(
            f"Created user '{user.username}' ({user.email}) with id={user.id} "
            "and initialized default profile."
        )
    return 0


async def _update_user(
    email: str,
    username: str | None,
    display_name: str | None,
    password: str | None,
    is_active: bool | None,
) -> int:
    await _ensure_schema()
    normalized_email = email.strip().lower()

    async with AsyncSessionLocal() as session:
        result = await session.execute(
            select(User).where(User.email == normalized_email)
        )
        user = result.scalar_one_or_none()
        if user is None:
            print(
                f"Error: user with email '{normalized_email}' not found.",
                file=sys.stderr,
            )
            return 1

        if username is not None:
            user.username = username.strip()
        if display_name is not None:
            user.display_name = display_name.strip()
        if password is not None:
            user.hashed_password = hash_password(password)
        if is_active is not None:
            user.is_active = is_active

        await session.commit()
        print(f"Updated user '{user.username}' ({user.email}).")
    return 0


async def _list_users() -> int:
    await _ensure_schema()
    async with AsyncSessionLocal() as session:
        result = await session.execute(select(User).order_by(User.created_at))
        users = result.scalars().all()
        if not users:
            print("No users found.")
            return 0
        for user in users:
            status_label = "active" if user.is_active else "inactive"
            print(
                f"- {user.id} | {user.username} | {user.email} | "
                f"{user.display_name} | {status_label}"
            )
    return 0


async def _import_ciqual(file_path: str | None) -> int:
    await _ensure_schema()
    async with AsyncSessionLocal() as session:
        stats = await import_ciqual(session, file_path=file_path)
        print(
            "Ciqual import completed: "
            f"created={stats.created}, updated={stats.updated}, skipped={stats.skipped}"
        )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m app.cli",
        description="MalviFactor account management CLI",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    create_parser = subparsers.add_parser(
        "create-user", help="Create a new user account and default profile"
    )
    create_parser.add_argument("--email", required=True, help="User email")
    create_parser.add_argument("--username", required=True, help="Unique username")
    create_parser.add_argument("--display-name", required=True, help="Display name")
    create_parser.add_argument("--password", required=True, help="Plain password")

    update_parser = subparsers.add_parser(
        "update-user", help="Update an existing user account"
    )
    update_parser.add_argument("--email", required=True, help="Target user email")
    update_parser.add_argument("--username", help="New username")
    update_parser.add_argument("--display-name", help="New display name")
    update_parser.add_argument("--password", help="New password")
    active_group = update_parser.add_mutually_exclusive_group()
    active_group.add_argument(
        "--active", action="store_true", dest="is_active", default=None
    )
    active_group.add_argument(
        "--inactive", action="store_false", dest="is_active", default=None
    )

    subparsers.add_parser("list-users", help="List all user accounts")

    ciqual_parser = subparsers.add_parser(
        "import-ciqual",
        help="Import or update official ANSES Ciqual food composition table",
    )
    ciqual_parser.add_argument(
        "--file",
        dest="file_path",
        default=None,
        help="Optional local path to a Ciqual .xlsx or .csv file",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.command == "create-user":
        return asyncio.run(
            _create_user(
                email=args.email,
                username=args.username,
                display_name=args.display_name,
                password=args.password,
            )
        )
    if args.command == "update-user":
        return asyncio.run(
            _update_user(
                email=args.email,
                username=args.username,
                display_name=args.display_name,
                password=args.password,
                is_active=args.is_active,
            )
        )
    if args.command == "list-users":
        return asyncio.run(_list_users())
    if args.command == "import-ciqual":
        return asyncio.run(_import_ciqual(file_path=args.file_path))

    parser.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
