"""Apply ReconFlow's exported Azure SQL schema using Microsoft Entra authentication."""

from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import struct
import subprocess

import pyodbc


DEFAULT_SERVER = "sql-reconflow-ep8odn.database.windows.net"
DEFAULT_DATABASE = "ReconFlowDemo"
SQL_FILE = Path(__file__).resolve().parents[1] / "sql" / "001_reconflow_schema.sql"
EXPECTED_TABLES = {
    "accounts_payable_rows",
    "accounts_receivable_rows",
    "ai_conversations",
    "ai_message_findings",
    "ai_messages",
    "assessment_answers",
    "audit_findings",
    "audit_runs",
    "cash_bank_rows",
    "documents",
    "finding_dispositions",
    "fixed_assets_rows",
    "general_ledger_rows",
    "inventory_rows",
    "ledger_imports",
    "requests",
    "source_columns",
    "tenants",
    "users",
}


def main() -> None:
    server = os.getenv("RECONFLOW_SQL_SERVER", DEFAULT_SERVER).strip()
    database = os.getenv("RECONFLOW_SQL_DATABASE", DEFAULT_DATABASE).strip()
    tenant_id = os.getenv("AZURE_TENANT_ID", "").strip()
    az_executable = shutil.which("az")
    if not server or not database:
        raise ValueError("RECONFLOW_SQL_SERVER and RECONFLOW_SQL_DATABASE cannot be empty.")
    if az_executable is None:
        raise RuntimeError("Azure CLI was not found. Sign in with `az login` and retry.")

    token_command = [
        az_executable,
        "account",
        "get-access-token",
        "--resource",
        "https://database.windows.net/",
        "--query",
        "accessToken",
        "--output",
        "tsv",
    ]
    if tenant_id:
        token_command.extend(["--tenant", tenant_id])
    result = subprocess.run(
        token_command,
        check=True,
        capture_output=True,
        text=True,
        timeout=60,
    )
    access_token = result.stdout.strip()
    if not access_token:
        raise RuntimeError("Azure CLI returned an empty SQL access token.")
    token_bytes = (
        struct.pack("=I", len(access_token.encode("utf-16-le")))
        + access_token.encode("utf-16-le")
    )
    drivers = pyodbc.drivers()
    driver = next(
        (
            candidate
            for candidate in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server")
            if candidate in drivers
        ),
        None,
    )
    if driver is None:
        raise RuntimeError(
            "Install Microsoft ODBC Driver 17 or 18 for SQL Server before applying the schema."
        )
    connection = pyodbc.connect(
        f"Driver={{{driver}}};"
        f"Server=tcp:{server},1433;"
        f"Database={database};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;"
        "Connection Timeout=60;",
        attrs_before={1256: token_bytes},
        autocommit=True,
    )
    try:
        cursor = connection.cursor()
        try:
            sql = SQL_FILE.read_text(encoding="utf-8")
            batches = [
                batch.strip()
                for batch in re.split(r"(?im)^\s*GO\s*$", sql)
                if batch.strip()
            ]
            for index, batch in enumerate(batches, start=1):
                cursor.execute(batch)
                print(f"Applied batch {index}/{len(batches)}")
            cursor.execute(
                "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES "
                "WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME"
            )
            tables = {row[0].lower() for row in cursor.fetchall()}
            missing_tables = EXPECTED_TABLES - tables
            if missing_tables:
                raise RuntimeError(
                    "Schema verification failed; expected tables are missing: "
                    + ", ".join(sorted(missing_tables))
                )
            print(f"Schema verified: {len(EXPECTED_TABLES)} expected tables are present.")
        finally:
            cursor.close()
    finally:
        connection.close()


if __name__ == "__main__":
    main()
