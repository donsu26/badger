from __future__ import annotations

import argparse
import sys

from . import config, history
from . import state as state_mod


def cmd_add(args) -> None:
    try:
        config.add_item(args.name, args.interval, args.start, args.end, args.days)
    except config.ConfigError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)
    print(f"added {args.name!r}")


def cmd_update(args) -> None:
    try:
        config.update_item(args.name, args.interval, args.start, args.end, args.days)
    except config.ConfigError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)
    print(f"updated {args.name!r}")


def cmd_remove(args) -> None:
    if config.remove_item(args.name):
        print(f"removed {args.name!r}")
    else:
        print(f"no such item: {args.name!r}", file=sys.stderr)
        sys.exit(1)


def cmd_list(args) -> None:
    try:
        items = config.load_items()
    except config.ConfigError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)
    if not items:
        print("(no items configured)")
        return
    for name, item in items.items():
        days_note = "every day" if item.days == config.ALL_DAYS else ",".join(config._format_days(item.days))
        print(
            f"{name}\tevery {item.interval_minutes}m\t"
            f"{item.window_start.strftime('%H:%M')}-{item.window_end.strftime('%H:%M')}\t{days_note}"
        )


def cmd_status(args) -> None:
    try:
        items = config.load_items()
    except config.ConfigError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)
    st = state_mod.load()
    now = state_mod.now()
    if not items:
        print("(no items configured)")
        return
    for name, item in items.items():
        entry = st.get(name, state_mod.default_entry())
        if now.date().weekday() not in item.days:
            window_note = "not scheduled today"
        else:
            in_window = item.window_start <= now.time() < item.window_end
            window_note = "in window" if in_window else "outside window"
        status_time = entry.get("status_time") or "-"
        print(f"{name}\t{entry.get('status', 'pending')}\t{status_time}\t({window_note})")


def cmd_history(args) -> None:
    records = history.query(item=args.item, days=args.days)
    if not records:
        print("(no history)")
        return
    for r in records:
        print(f"{r['timestamp']}\t{r['item']}\t{r['event']}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="nagger", description="Local Nagger checklist reminders")
    sub = parser.add_subparsers(dest="command", required=True)

    p_add = sub.add_parser("add", help="add a checklist item")
    p_add.add_argument("name")
    p_add.add_argument("--interval", type=int, default=None, help="minutes between nags")
    p_add.add_argument("--start", default=None, help="window start HH:MM")
    p_add.add_argument("--end", default=None, help="window end HH:MM")
    p_add.add_argument(
        "--days",
        default=None,
        help="comma-separated days (mon,tue,...) or weekdays/weekends/all; default all days",
    )
    p_add.set_defaults(func=cmd_add)

    p_update = sub.add_parser("update", help="update an existing checklist item")
    p_update.add_argument("name")
    p_update.add_argument("--interval", type=int, default=None, help="minutes between nags")
    p_update.add_argument("--start", default=None, help="window start HH:MM")
    p_update.add_argument("--end", default=None, help="window end HH:MM")
    p_update.add_argument(
        "--days",
        default=None,
        help="comma-separated days (mon,tue,...) or weekdays/weekends/all",
    )
    p_update.set_defaults(func=cmd_update)

    p_remove = sub.add_parser("remove", help="remove a checklist item")
    p_remove.add_argument("name")
    p_remove.set_defaults(func=cmd_remove)

    p_list = sub.add_parser("list", help="list checklist items")
    p_list.set_defaults(func=cmd_list)

    p_status = sub.add_parser("status", help="show today's status")
    p_status.set_defaults(func=cmd_status)

    p_history = sub.add_parser("history", help="show event history")
    p_history.add_argument("--item", default=None)
    p_history.add_argument("--days", type=int, default=7)
    p_history.set_defaults(func=cmd_history)

    return parser


def main(argv=None) -> None:
    parser = build_parser()
    args = parser.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
