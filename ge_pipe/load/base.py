from contextlib import contextmanager
from typing import Generator

import psycopg2
import psycopg2.extensions

from ge_pipe.settings import settings


@contextmanager
def get_conn() -> Generator[psycopg2.extensions.connection, None, None]:
    conn = psycopg2.connect(settings.postgres_dsn)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
