"""The store's SQL run against in-memory SQLite, for tests of tables with real queries
(buddy pairs and notes). Translates the few MySQL/SingleStore spellings the store uses."""
import re
import sqlite3
from datetime import datetime

from harness import store


def translate(sql: str) -> str:
    sql = " ".join(sql.split())
    sql = sql.replace("%s", "?").replace("INSERT IGNORE", "INSERT OR IGNORE")
    sql = re.sub(r", (SHARD|SORT) KEY \([^)]*\)", "", sql)
    sql = re.sub(r"DATETIME\(6\)|DATETIME|JSON", "TEXT", sql)
    return sql


def _arg(value):
    return value.isoformat(sep=" ") if isinstance(value, datetime) else value


class Cursor:
    def __init__(self, conn, db):
        self.conn, self.cur = conn, db.cursor()

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, args=()):
        if self.conn.fail:
            raise RuntimeError("write failed")
        self.cur.execute(translate(sql), tuple(_arg(a) for a in args))

    def executemany(self, sql, seq):
        for args in seq:
            self.execute(sql, args)

    @property
    def rowcount(self):
        return self.cur.rowcount

    def fetchone(self):
        return self.cur.fetchone()

    def fetchall(self):
        return self.cur.fetchall()


class Conn:
    def __init__(self):
        self.fail = False
        self.db = sqlite3.connect(":memory:", check_same_thread=False)
        for stmt in store.DDL:
            self.db.execute(translate(stmt))

    def cursor(self):
        return Cursor(self, self.db)

    def rows(self, table: str) -> list[tuple]:
        return self.db.execute(f"SELECT * FROM {table}").fetchall()
