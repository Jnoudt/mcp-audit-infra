SET XACT_ABORT ON;
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.[tenants]', N'U') IS NULL
BEGIN
    CREATE TABLE tenants (
	tenant_id VARCHAR(128) NOT NULL, 
	created_at DATETIMEOFFSET NOT NULL, 
	PRIMARY KEY (tenant_id)
);
END
GO
IF OBJECT_ID(N'dbo.[users]', N'U') IS NULL
BEGIN
    CREATE TABLE users (
	tenant_id VARCHAR(128) NOT NULL, 
	user_id VARCHAR(128) NOT NULL, 
	email VARCHAR(320) NOT NULL, 
	display_name VARCHAR(256) NOT NULL, 
	created_at DATETIMEOFFSET NOT NULL, 
	PRIMARY KEY (tenant_id, user_id), 
	FOREIGN KEY(tenant_id) REFERENCES tenants (tenant_id) ON DELETE CASCADE
);
END
GO
IF OBJECT_ID(N'dbo.[requests]', N'U') IS NULL
BEGIN
    CREATE TABLE requests (
	tenant_id VARCHAR(128) NOT NULL, 
	request_id VARCHAR(128) NOT NULL, 
	owner_user_id VARCHAR(128) NOT NULL, 
	service_id VARCHAR(128) NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	created_at DATETIMEOFFSET NOT NULL, 
	modified_at DATETIMEOFFSET NOT NULL, 
	PRIMARY KEY (tenant_id, request_id), 
	FOREIGN KEY(tenant_id, owner_user_id) REFERENCES users (tenant_id, user_id) ON DELETE NO ACTION, 
	UNIQUE (tenant_id, request_id, owner_user_id)
);
END
GO
IF OBJECT_ID(N'dbo.[assessment_answers]', N'U') IS NULL
BEGIN
    CREATE TABLE assessment_answers (
	tenant_id VARCHAR(128) NOT NULL, 
	request_id VARCHAR(128) NOT NULL, 
	question_id VARCHAR(128) NOT NULL, 
	answer_json NVARCHAR(MAX) NOT NULL, 
	updated_at DATETIMEOFFSET NOT NULL, 
	PRIMARY KEY (tenant_id, request_id, question_id), 
	FOREIGN KEY(tenant_id, request_id) REFERENCES requests (tenant_id, request_id) ON DELETE CASCADE
);
END
GO
IF OBJECT_ID(N'dbo.[audit_runs]', N'U') IS NULL
BEGIN
    CREATE TABLE audit_runs (
	tenant_id VARCHAR(128) NOT NULL, 
	run_id VARCHAR(128) NOT NULL, 
	request_id VARCHAR(128) NOT NULL, 
	owner_user_id VARCHAR(128) NOT NULL, 
	status VARCHAR(32) NOT NULL, 
	rule_version VARCHAR(64) NOT NULL, 
	created_at DATETIMEOFFSET NOT NULL, 
	completed_at DATETIMEOFFSET NULL, 
	summary_json NVARCHAR(MAX) NOT NULL, 
	PRIMARY KEY (tenant_id, run_id), 
	FOREIGN KEY(tenant_id, request_id, owner_user_id) REFERENCES requests (tenant_id, request_id, owner_user_id) ON DELETE NO ACTION, 
	UNIQUE (tenant_id, run_id, request_id, owner_user_id)
);
END
GO
IF OBJECT_ID(N'dbo.[documents]', N'U') IS NULL
BEGIN
    CREATE TABLE documents (
	tenant_id VARCHAR(128) NOT NULL, 
	document_id VARCHAR(128) NOT NULL, 
	request_id VARCHAR(128) NOT NULL, 
	owner_user_id VARCHAR(128) NOT NULL, 
	blob_name VARCHAR(512) NOT NULL, 
	original_file_name VARCHAR(255) NOT NULL, 
	content_type VARCHAR(128) NOT NULL, 
	content_sha256 VARCHAR(64) NOT NULL, 
	size_bytes BIGINT NOT NULL, 
	created_at DATETIMEOFFSET NOT NULL, 
	modified_at DATETIMEOFFSET NOT NULL, 
	PRIMARY KEY (tenant_id, document_id), 
	FOREIGN KEY(tenant_id, request_id, owner_user_id) REFERENCES requests (tenant_id, request_id, owner_user_id) ON DELETE NO ACTION, 
	UNIQUE (tenant_id, document_id, request_id, owner_user_id), 
	UNIQUE (blob_name)
);
END
GO
IF OBJECT_ID(N'dbo.[ai_conversations]', N'U') IS NULL
BEGIN
    CREATE TABLE ai_conversations (
	tenant_id VARCHAR(128) NOT NULL, 
	conversation_id VARCHAR(128) NOT NULL, 
	request_id VARCHAR(128) NOT NULL, 
	owner_user_id VARCHAR(128) NOT NULL, 
	run_id VARCHAR(128) NOT NULL, 
	created_at DATETIMEOFFSET NOT NULL, 
	modified_at DATETIMEOFFSET NOT NULL, 
	PRIMARY KEY (tenant_id, conversation_id), 
	FOREIGN KEY(tenant_id, request_id, owner_user_id) REFERENCES requests (tenant_id, request_id, owner_user_id) ON DELETE CASCADE, 
	FOREIGN KEY(tenant_id, run_id, request_id, owner_user_id) REFERENCES audit_runs (tenant_id, run_id, request_id, owner_user_id) ON DELETE NO ACTION, 
	UNIQUE (tenant_id, conversation_id, request_id, owner_user_id)
);
END
GO
IF OBJECT_ID(N'dbo.[ledger_imports]', N'U') IS NULL
BEGIN
    CREATE TABLE ledger_imports (
	tenant_id VARCHAR(128) NOT NULL, 
	import_id VARCHAR(128) NOT NULL, 
	document_id VARCHAR(128) NOT NULL, 
	request_id VARCHAR(128) NOT NULL, 
	owner_user_id VARCHAR(128) NOT NULL, 
	ledger_type VARCHAR(64) NOT NULL, 
	source_system VARCHAR(128) NOT NULL, 
	schema_version INTEGER NOT NULL, 
	row_count BIGINT NOT NULL, 
	created_at DATETIMEOFFSET NOT NULL, 
	PRIMARY KEY (tenant_id, import_id), 
	FOREIGN KEY(tenant_id, document_id, request_id, owner_user_id) REFERENCES documents (tenant_id, document_id, request_id, owner_user_id) ON DELETE NO ACTION, 
	UNIQUE (tenant_id, import_id, document_id, request_id, owner_user_id)
);
END
GO
IF OBJECT_ID(N'dbo.[accounts_payable_rows]', N'U') IS NULL
BEGIN
    CREATE TABLE accounts_payable_rows (
	tenant_id VARCHAR(128) NOT NULL, 
	import_id VARCHAR(128) NOT NULL, 
	row_number BIGINT NOT NULL, 
	document_id VARCHAR(128) NOT NULL, 
	request_id VARCHAR(128) NOT NULL, 
	owner_user_id VARCHAR(128) NOT NULL, 
	company_code VARCHAR(128) NULL, 
	vendor_id VARCHAR(128) NOT NULL, 
	transaction_id VARCHAR(128) NULL, 
	invoice_number VARCHAR(128) NOT NULL, 
	invoice_date DATE NOT NULL, 
	posting_date DATE NULL, 
	purchase_order VARCHAR(128) NULL, 
	amount NUMERIC(30, 8) NOT NULL, 
	currency VARCHAR(3) NULL, 
	tax_code VARCHAR(128) NULL, 
	source_payload_json NVARCHAR(MAX) NOT NULL, 
	PRIMARY KEY (tenant_id, import_id, row_number), 
	FOREIGN KEY(tenant_id, import_id, document_id, request_id, owner_user_id) REFERENCES ledger_imports (tenant_id, import_id, document_id, request_id, owner_user_id) ON DELETE CASCADE
);
END
GO
IF OBJECT_ID(N'dbo.[accounts_receivable_rows]', N'U') IS NULL
BEGIN
    CREATE TABLE accounts_receivable_rows (
	tenant_id VARCHAR(128) NOT NULL, 
	import_id VARCHAR(128) NOT NULL, 
	row_number BIGINT NOT NULL, 
	document_id VARCHAR(128) NOT NULL, 
	request_id VARCHAR(128) NOT NULL, 
	owner_user_id VARCHAR(128) NOT NULL, 
	company_code VARCHAR(128) NULL, 
	customer_id VARCHAR(128) NOT NULL, 
	transaction_id VARCHAR(128) NULL, 
	invoice_number VARCHAR(128) NOT NULL, 
	invoice_date DATE NOT NULL, 
	posting_date DATE NULL, 
	due_date DATE NULL, 
	amount NUMERIC(30, 8) NOT NULL, 
	currency VARCHAR(3) NULL, 
	tax_code VARCHAR(128) NULL, 
	source_payload_json NVARCHAR(MAX) NOT NULL, 
	PRIMARY KEY (tenant_id, import_id, row_number), 
	FOREIGN KEY(tenant_id, import_id, document_id, request_id, owner_user_id) REFERENCES ledger_imports (tenant_id, import_id, document_id, request_id, owner_user_id) ON DELETE CASCADE
);
END
GO
IF OBJECT_ID(N'dbo.[ai_messages]', N'U') IS NULL
BEGIN
    CREATE TABLE ai_messages (
	tenant_id VARCHAR(128) NOT NULL, 
	message_id VARCHAR(128) NOT NULL, 
	conversation_id VARCHAR(128) NOT NULL, 
	request_id VARCHAR(128) NOT NULL, 
	owner_user_id VARCHAR(128) NOT NULL, 
	role VARCHAR(16) NOT NULL, 
	content NVARCHAR(MAX) NOT NULL, 
	provider VARCHAR(64) NOT NULL, 
	model_deployment VARCHAR(128) NOT NULL, 
	prompt_tokens INTEGER NULL, 
	completion_tokens INTEGER NULL, 
	created_at DATETIMEOFFSET NOT NULL, 
	PRIMARY KEY (tenant_id, message_id), 
	FOREIGN KEY(tenant_id, conversation_id, request_id, owner_user_id) REFERENCES ai_conversations (tenant_id, conversation_id, request_id, owner_user_id) ON DELETE CASCADE, 
	UNIQUE (tenant_id, message_id, request_id, owner_user_id)
);
END
GO
IF OBJECT_ID(N'dbo.[audit_findings]', N'U') IS NULL
BEGIN
    CREATE TABLE audit_findings (
	tenant_id VARCHAR(128) NOT NULL, 
	finding_id VARCHAR(128) NOT NULL, 
	run_id VARCHAR(128) NOT NULL, 
	request_id VARCHAR(128) NOT NULL, 
	owner_user_id VARCHAR(128) NOT NULL, 
	import_id VARCHAR(128) NOT NULL, 
	document_id VARCHAR(128) NOT NULL, 
	source_row_number BIGINT NULL, 
	rule_code VARCHAR(128) NOT NULL, 
	severity VARCHAR(32) NOT NULL, 
	title VARCHAR(256) NOT NULL, 
	description NVARCHAR(MAX) NOT NULL, 
	recommendation NVARCHAR(MAX) NOT NULL, 
	evidence_json NVARCHAR(MAX) NOT NULL, 
	created_at DATETIMEOFFSET NOT NULL, 
	PRIMARY KEY (tenant_id, finding_id), 
	FOREIGN KEY(tenant_id, run_id, request_id, owner_user_id) REFERENCES audit_runs (tenant_id, run_id, request_id, owner_user_id) ON DELETE CASCADE, 
	FOREIGN KEY(tenant_id, import_id) REFERENCES ledger_imports (tenant_id, import_id) ON DELETE NO ACTION, 
	FOREIGN KEY(tenant_id, document_id, request_id, owner_user_id) REFERENCES documents (tenant_id, document_id, request_id, owner_user_id) ON DELETE NO ACTION, 
	UNIQUE (tenant_id, finding_id, run_id, request_id, owner_user_id)
);
END
GO
IF OBJECT_ID(N'dbo.[cash_bank_rows]', N'U') IS NULL
BEGIN
    CREATE TABLE cash_bank_rows (
	tenant_id VARCHAR(128) NOT NULL, 
	import_id VARCHAR(128) NOT NULL, 
	row_number BIGINT NOT NULL, 
	document_id VARCHAR(128) NOT NULL, 
	request_id VARCHAR(128) NOT NULL, 
	owner_user_id VARCHAR(128) NOT NULL, 
	company_code VARCHAR(128) NULL, 
	bank_account VARCHAR(128) NOT NULL, 
	account_identifier VARCHAR(128) NULL, 
	transaction_id VARCHAR(128) NOT NULL, 
	value_date DATE NOT NULL, 
	posting_date DATE NULL, 
	payment_type VARCHAR(128) NULL, 
	amount NUMERIC(30, 8) NOT NULL, 
	currency VARCHAR(3) NULL, 
	reference NVARCHAR(MAX) NULL, 
	source_payload_json NVARCHAR(MAX) NOT NULL, 
	PRIMARY KEY (tenant_id, import_id, row_number), 
	FOREIGN KEY(tenant_id, import_id, document_id, request_id, owner_user_id) REFERENCES ledger_imports (tenant_id, import_id, document_id, request_id, owner_user_id) ON DELETE CASCADE
);
END
GO
IF OBJECT_ID(N'dbo.[fixed_assets_rows]', N'U') IS NULL
BEGIN
    CREATE TABLE fixed_assets_rows (
	tenant_id VARCHAR(128) NOT NULL, 
	import_id VARCHAR(128) NOT NULL, 
	row_number BIGINT NOT NULL, 
	document_id VARCHAR(128) NOT NULL, 
	request_id VARCHAR(128) NOT NULL, 
	owner_user_id VARCHAR(128) NOT NULL, 
	company_code VARCHAR(128) NULL, 
	asset_id VARCHAR(128) NOT NULL, 
	asset_class VARCHAR(128) NULL, 
	description NVARCHAR(MAX) NULL, 
	in_service_date DATE NULL, 
	useful_life_years NUMERIC(12, 4) NULL, 
	acquisition_cost NUMERIC(30, 8) NOT NULL, 
	accumulated_depreciation NUMERIC(30, 8) NOT NULL, 
	period_depreciation NUMERIC(30, 8) NULL, 
	currency VARCHAR(3) NULL, 
	source_payload_json NVARCHAR(MAX) NOT NULL, 
	PRIMARY KEY (tenant_id, import_id, row_number), 
	FOREIGN KEY(tenant_id, import_id, document_id, request_id, owner_user_id) REFERENCES ledger_imports (tenant_id, import_id, document_id, request_id, owner_user_id) ON DELETE CASCADE
);
END
GO
IF OBJECT_ID(N'dbo.[general_ledger_rows]', N'U') IS NULL
BEGIN
    CREATE TABLE general_ledger_rows (
	tenant_id VARCHAR(128) NOT NULL, 
	import_id VARCHAR(128) NOT NULL, 
	row_number BIGINT NOT NULL, 
	document_id VARCHAR(128) NOT NULL, 
	request_id VARCHAR(128) NOT NULL, 
	owner_user_id VARCHAR(128) NOT NULL, 
	company_code VARCHAR(128) NULL, 
	document_number VARCHAR(128) NOT NULL, 
	fiscal_year INTEGER NULL, 
	document_type VARCHAR(64) NULL, 
	posting_date DATE NOT NULL, 
	account_code VARCHAR(128) NOT NULL, 
	cost_center VARCHAR(128) NULL, 
	direction VARCHAR(16) NULL, 
	amount NUMERIC(30, 8) NOT NULL, 
	currency VARCHAR(3) NULL, 
	description NVARCHAR(MAX) NULL, 
	source_payload_json NVARCHAR(MAX) NOT NULL, 
	PRIMARY KEY (tenant_id, import_id, row_number), 
	FOREIGN KEY(tenant_id, import_id, document_id, request_id, owner_user_id) REFERENCES ledger_imports (tenant_id, import_id, document_id, request_id, owner_user_id) ON DELETE CASCADE
);
END
GO
IF OBJECT_ID(N'dbo.[inventory_rows]', N'U') IS NULL
BEGIN
    CREATE TABLE inventory_rows (
	tenant_id VARCHAR(128) NOT NULL, 
	import_id VARCHAR(128) NOT NULL, 
	row_number BIGINT NOT NULL, 
	document_id VARCHAR(128) NOT NULL, 
	request_id VARCHAR(128) NOT NULL, 
	owner_user_id VARCHAR(128) NOT NULL, 
	location VARCHAR(128) NULL, 
	item_id VARCHAR(128) NOT NULL, 
	description NVARCHAR(MAX) NULL, 
	movement_type VARCHAR(128) NOT NULL, 
	reference_number VARCHAR(128) NULL, 
	posting_date DATE NOT NULL, 
	quantity NUMERIC(30, 8) NOT NULL, 
	unit_of_measure VARCHAR(32) NULL, 
	unit_cost NUMERIC(30, 8) NULL, 
	total_cost NUMERIC(30, 8) NULL, 
	currency VARCHAR(3) NULL, 
	source_payload_json NVARCHAR(MAX) NOT NULL, 
	PRIMARY KEY (tenant_id, import_id, row_number), 
	FOREIGN KEY(tenant_id, import_id, document_id, request_id, owner_user_id) REFERENCES ledger_imports (tenant_id, import_id, document_id, request_id, owner_user_id) ON DELETE CASCADE
);
END
GO
IF OBJECT_ID(N'dbo.[source_columns]', N'U') IS NULL
BEGIN
    CREATE TABLE source_columns (
	tenant_id VARCHAR(128) NOT NULL, 
	import_id VARCHAR(128) NOT NULL, 
	ordinal INTEGER NOT NULL, 
	source_name VARCHAR(128) NOT NULL, 
	canonical_name VARCHAR(128) NULL, 
	inferred_type VARCHAR(32) NOT NULL, 
	is_nullable BIT NOT NULL, 
	analysis_allowed BIT NOT NULL, 
	PRIMARY KEY (tenant_id, import_id, ordinal), 
	FOREIGN KEY(tenant_id, import_id) REFERENCES ledger_imports (tenant_id, import_id) ON DELETE CASCADE
);
END
GO
IF OBJECT_ID(N'dbo.[ai_message_findings]', N'U') IS NULL
BEGIN
    CREATE TABLE ai_message_findings (
	tenant_id VARCHAR(128) NOT NULL, 
	message_id VARCHAR(128) NOT NULL, 
	finding_id VARCHAR(128) NOT NULL, 
	run_id VARCHAR(128) NOT NULL, 
	request_id VARCHAR(128) NOT NULL, 
	owner_user_id VARCHAR(128) NOT NULL, 
	PRIMARY KEY (tenant_id, message_id, finding_id), 
	FOREIGN KEY(tenant_id, message_id, request_id, owner_user_id) REFERENCES ai_messages (tenant_id, message_id, request_id, owner_user_id) ON DELETE CASCADE, 
	FOREIGN KEY(tenant_id, finding_id, run_id, request_id, owner_user_id) REFERENCES audit_findings (tenant_id, finding_id, run_id, request_id, owner_user_id) ON DELETE NO ACTION
);
END
GO
IF OBJECT_ID(N'dbo.[finding_dispositions]', N'U') IS NULL
BEGIN
    CREATE TABLE finding_dispositions (
	tenant_id VARCHAR(128) NOT NULL, 
	disposition_id VARCHAR(128) NOT NULL, 
	finding_id VARCHAR(128) NOT NULL, 
	run_id VARCHAR(128) NOT NULL, 
	request_id VARCHAR(128) NOT NULL, 
	owner_user_id VARCHAR(128) NOT NULL, 
	disposition VARCHAR(32) NOT NULL, 
	reviewer_note NVARCHAR(MAX) NOT NULL, 
	created_at DATETIMEOFFSET NOT NULL, 
	PRIMARY KEY (tenant_id, disposition_id), 
	FOREIGN KEY(tenant_id, finding_id, run_id, request_id, owner_user_id) REFERENCES audit_findings (tenant_id, finding_id, run_id, request_id, owner_user_id) ON DELETE NO ACTION
);
END
GO
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'ix_documents_owner_modified' AND object_id = OBJECT_ID(N'dbo.[documents]')
)
BEGIN
    CREATE INDEX ix_documents_owner_modified ON documents (tenant_id, owner_user_id, modified_at);
END
GO
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'ix_audit_findings_run' AND object_id = OBJECT_ID(N'dbo.[audit_findings]')
)
BEGIN
    CREATE INDEX ix_audit_findings_run ON audit_findings (tenant_id, run_id, rule_code);
END
GO
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'ix_general_ledger_owner' AND object_id = OBJECT_ID(N'dbo.[general_ledger_rows]')
)
BEGIN
    CREATE INDEX ix_general_ledger_owner ON general_ledger_rows (tenant_id, owner_user_id, request_id);
END
GO
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'ix_accounts_receivable_owner' AND object_id = OBJECT_ID(N'dbo.[accounts_receivable_rows]')
)
BEGIN
    CREATE INDEX ix_accounts_receivable_owner ON accounts_receivable_rows (tenant_id, owner_user_id, request_id);
END
GO
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'ix_accounts_payable_owner' AND object_id = OBJECT_ID(N'dbo.[accounts_payable_rows]')
)
BEGIN
    CREATE INDEX ix_accounts_payable_owner ON accounts_payable_rows (tenant_id, owner_user_id, request_id);
END
GO
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'ix_fixed_assets_owner' AND object_id = OBJECT_ID(N'dbo.[fixed_assets_rows]')
)
BEGIN
    CREATE INDEX ix_fixed_assets_owner ON fixed_assets_rows (tenant_id, owner_user_id, request_id);
END
GO
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'ix_inventory_owner' AND object_id = OBJECT_ID(N'dbo.[inventory_rows]')
)
BEGIN
    CREATE INDEX ix_inventory_owner ON inventory_rows (tenant_id, owner_user_id, request_id);
END
GO
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'ix_cash_bank_owner' AND object_id = OBJECT_ID(N'dbo.[cash_bank_rows]')
)
BEGIN
    CREATE INDEX ix_cash_bank_owner ON cash_bank_rows (tenant_id, owner_user_id, request_id);
END
GO
