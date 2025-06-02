#!/usr/bin/env python3

import argparse
import os
import sqlite3
from pathlib import Path
from typing import List
from dotenv import load_dotenv

def collect_sql_files(paths: List[Path]) -> List[Path]:
    sql_files = []
    for path in paths:
        if path.is_file() and path.suffix == ".sql":
            sql_files.append(path)
        elif path.is_dir():
            sql_files.extend(sorted(p for p in path.rglob("*.sql") if p.is_file()))
    return sorted(sql_files)

def execute_sql_files(db_path: Path, sql_files: List[Path]):
    if not sql_files:
        print("No .sql files found to execute.")
        return

    print(f"Connecting to SQLite DB: {db_path}")
    with sqlite3.connect(db_path) as conn:
        for sql_file in sql_files:
            print(f"Executing: {sql_file}")
            with open(sql_file, encoding='utf-8') as f:
                conn.executescript(f.read())
    print("Execution complete.")

def main():
    parser = argparse.ArgumentParser(description="Execute .sql files on SQLite DB")
    parser.add_argument("paths", nargs="+", type=Path, help="Paths to .sql files or directories")
    parser.add_argument("--env", type=Path, help=".env file path (default: ./.env)", default=Path(".env"))

    args = parser.parse_args()

    if args.env.exists():
        load_dotenv(dotenv_path=args.env)
    else:
        print(f"Warning: .env file not found at {args.env}, proceeding with default env")

    db_path_str = os.getenv("SQLITE_DB_PATH")
    if not db_path_str:
        print("Error: SQLITE_DB_PATH not set in .env")
        exit(1)

    db_path = Path(db_path_str)
    db_path.parent.mkdir(parents=True, exist_ok=True)

    sql_files = collect_sql_files(args.paths)
    execute_sql_files(db_path, sql_files)

if __name__ == "__main__":
    main()

