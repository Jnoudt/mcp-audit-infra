"""Generate Azure SQL DDL from the app's reviewed SQLAlchemy model."""

from __future__ import annotations

from pathlib import Path
import sys

INFRA_ROOT = Path(__file__).resolve().parents[1]
APP_ROOT = INFRA_ROOT.parent / "mcp-audit-server"
sys.path.insert(0, str(APP_ROOT))

from sqlalchemy.dialects import mssql
from sqlalchemy.schema import CreateIndex, CreateTable

from src.ingestion.schema_builder import metadata


OUTPUT_PATH = INFRA_ROOT / "sql" / "001_reconflow_schema.sql"


def main() -> None:
    dialect = mssql.dialect()
    statements = ["SET XACT_ABORT ON;", "SET ANSI_NULLS ON;", "SET QUOTED_IDENTIFIER ON;"]

    for table in metadata.sorted_tables:
        create_table = str(CreateTable(table).compile(dialect=dialect)).strip().rstrip(";")
        statements.append(
            "IF OBJECT_ID(N'dbo.[{name}]', N'U') IS NULL\n"
            "BEGIN\n    {create_table};\nEND".format(
                name=table.name,
                create_table=create_table,
            )
        )

    for table_name in (
        "documents",
        "audit_findings",
        "general_ledger_rows",
        "accounts_receivable_rows",
        "accounts_payable_rows",
        "fixed_assets_rows",
        "inventory_rows",
        "cash_bank_rows",
    ):
        table = metadata.tables[table_name]
        for index in table.indexes:
            if index.name:
                assert isinstance(index, object)
                assert index.table is not None
                assert index.name is not None
                create_index = str(CreateIndex(index).compile(dialect=dialect)).strip().rstrip(";")
                statements.append(
                    "IF NOT EXISTS (\n"
                    "    SELECT 1 FROM sys.indexes\n"
                    "    WHERE name = N'{index_name}' AND object_id = OBJECT_ID(N'dbo.[{table_name}]')\n"
                    ")\nBEGIN\n    {create_index};\nEND".format(
                        index_name=index.name,
                        table_name=index.table.name,
                        create_index=create_index,
                    )
                )

    statements = [
        statement.replace("ON DELETE RESTRICT", "ON DELETE NO ACTION")
        .replace(" TEXT ", " NVARCHAR(MAX) ")
        .replace(" TEXT,", " NVARCHAR(MAX),")
        .replace("invoice_date DATETIME", "invoice_date DATE")
        .replace("posting_date DATETIME", "posting_date DATE")
        .replace("due_date DATETIME", "due_date DATE")
        .replace("value_date DATETIME", "value_date DATE")
        .replace("in_service_date DATETIME", "in_service_date DATE")
        for statement in statements
    ]

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text("\nGO\n".join(statements) + "\nGO\n", encoding="utf-8")
    print(OUTPUT_PATH)


if __name__ == "__main__":
    main()
