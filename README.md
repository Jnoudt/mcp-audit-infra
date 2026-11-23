# Remote MCP Tool Server — Infrastructure

Terraform infrastructure for the Remote MCP Tool Server's domain and audit workflows. The application code is maintained separately in `mcp-audit-server`.

## Current scope: test/demo only

The current demo resources are in `rg-mcp-audit-dev`; they were created outside this Terraform state. The local frontend can call the existing hosted Function API, and local AI calls can use the existing Foundry endpoint when explicitly enabled. Reconcile/import the live resources before using this Terraform root to manage them.

**Do not apply this Terraform root as-is.** It configures a broader stack—including Functions, two Storage accounts, Cosmos DB, Key Vault, Log Analytics, and Application Insights—and would create resources that are not reconciled with the existing demo resources. It can optionally configure an existing Foundry endpoint and grant the Terraform-created Function identity access, but it does not create a Foundry hub, project, or model deployment. No cloud resources were created or changed by these code edits. Before any apply, reconcile the Terraform state and resource names, inspect the saved plan, verify quota/pricing/free-offer eligibility, and obtain explicit approval. Use synthetic test files only.

ACS Email, customer identity, billing, production hosting, private networking, and production monitoring/backups are deferred. The supplied local Azure inventory/credentials file must not be copied into source, Terraform variables, logs, chat, or GitHub.

## Resources configured by the current full-stack Terraform root (if applied)

- Azure Resource Group, Linux Flex Consumption (FC1) Function App, and runtime/deployment Storage Account
- Cosmos DB SQL API account/database/container with a system-assigned identity data-plane role
- Azure SQL logical server with Entra-only administration and a General Purpose serverless free-tier database
- Separate evidence Blob Storage Account with a private documents container and managed-identity data access
- Azure Key Vault using Azure RBAC, plus a system-assigned identity secrets-reader role
- Log Analytics workspace and workspace-based Application Insights
- Optional role assignment and endpoint settings for an existing Microsoft Foundry account/model deployment (AI remains disabled by default)
- GitHub Actions plan/apply workflow authenticated with Azure OIDC

The Function App uses Flex Consumption (FC1), the current Linux serverless plan. The legacy Linux Consumption (Y1) plan is scheduled to retire on September 30, 2028. Flex Consumption includes monthly free grants, but usage beyond those grants is billed; validate current Azure pricing and quotas before deployment. Python 3.12 is selected for the Function App.

The Cosmos DB account uses provisioned throughput because Cosmos DB free tier is not compatible with serverless mode. The container starts at 400 RU/s. `enable_cosmos_free_tier` defaults to `true` and the example variables file also sets it to `true`. Use it only if the subscription is eligible and has no other Cosmos DB free-tier account. Free-tier eligibility and regional availability are controlled by Azure and are not guaranteed by Terraform.

The relational database uses Azure SQL's monthly free limit through the stable SQL ARM API because AzureRM does not expose `useFreeLimit` or `freeLimitExhaustionBehavior`. It is configured to pause when the monthly free limit is exhausted and after 60 minutes of inactivity. Free-tier availability depends on subscription eligibility and is limited by Azure; verify current eligibility before applying. The SQL public endpoint has no firewall allow rules by default; set `sql_firewall_allowlist` to a trusted developer's public IPv4 address for local testing. The Terraform-created Function still needs a contained database user/role and an approved network path before it can connect. The existing app does not yet persist requests or uploads to Azure SQL.

Evidence documents are stored in a separate Standard/LRS account with Shared Key access and anonymous container access disabled. The storage and Key Vault endpoints remain public for low-cost local development, but Entra authentication, RBAC, and private container access are required. This is not production network isolation; private endpoints/VNet integration or another verified allowlist design must be added before handling production audit evidence. The Function identity receives `Storage Blob Data Contributor`. The upload API, per-user authorization, SQL migrations, and document retention policy are application work and are not created by this Terraform module.

This Terraform root does not create an Azure AI Foundry resource, project, or model deployment. When `foundry_resource_id`, `foundry_openai_base_url`, and `foundry_model_deployment` are supplied, it grants the Terraform-created Function's system-assigned identity the `Cognitive Services OpenAI User` role at the existing account scope and configures the endpoint/deployment. `RECONFLOW_AI_ENABLED` remains `false`; enable AI separately only after confirming the model, region, quota, data handling, and expected cost. There is no guaranteed no-cost cloud AI endpoint.

The current Function uses a system-assigned managed identity for Foundry and Storage access; those role assignments were verified on the live demo deployment. The existing demo currently calls public Azure endpoints successfully without a VNet. No VNet/private endpoints are configured in this Terraform root or present in the inspected resource group. Private networking is not required for the current public-endpoint demo, but should be designed before production or private-only data access.

The low-cost Terraform profile intentionally leaves storage and Key Vault public network endpoints enabled. Consequently, Trivy reports `AZU-0012` for both storage accounts and `AZU-0013` for Key Vault. These are documented dev-only risks, not suppressions; the IaC is **not deployment-ready** until a private or verified allowlisted network design is implemented. Do not change the ACLs to `Deny` until Function runtime, local access, deployment, and state-backend connectivity are all accounted for.

Set `sql_administrator_login` and `sql_administrator_object_id` in a private `terraform.tfvars` or deployment variables before planning. Do not commit credentials or secrets. The SQL administrator is Entra-only; no SQL password is stored in Terraform state.

## Bootstrap and deploy

1. Create a dedicated Azure Storage Account and blob container for Terraform state. This bootstrap storage is intentionally not managed by this state.
2. Grant the GitHub OIDC identity `Storage Blob Data Contributor` on the state container, and sufficient Azure permissions to create the resources and role assignments in the target subscription/resource group. The workflow identity also needs `Storage Blob Data Contributor` on the runtime storage account; Terraform grants this role to the authenticated deployer so it can manage the private deployment container using Entra ID.
3. Configure the GitHub `dev` environment with secrets `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID`; add variables `TF_STATE_RG`, `TF_STATE_SA`, `TF_STATE_CONTAINER`, `SQL_ADMINISTRATOR_LOGIN`, and `SQL_ADMINISTRATOR_OBJECT_ID`. Add `FOUNDRY_RESOURCE_ID`, `FOUNDRY_OPENAI_BASE_URL`, and `FOUNDRY_MODEL_DEPLOYMENT` only if you intentionally wire an existing Foundry deployment into the Terraform-created Function.
4. Configure an Azure federated identity credential for this repository's GitHub `dev` environment. Do not create client secrets.
5. Push a branch and open a PR to run checks. Merges/pushes to `main` and `workflow_dispatch` run a Terraform plan only; the GitHub workflow has no apply step. Apply is a separate, explicit local operation after reviewing the saved plan and resolving resource/state reconciliation, cost, and security findings.

The state backend uses Azure AD/OIDC authentication, so no storage account key is needed for Terraform state access. The Function App uses managed identity for host and deployment storage. Terraform state can still contain sensitive provider attributes and must be access-controlled and never committed.

## Local use

Run the local IaC checks with `pwsh ./scripts/check-iac.ps1`. They require Terraform and Trivy. The current checks previously passed `terraform fmt`, init, and validate, but Trivy reports the three network findings listed above; Terraform deployment readiness has not passed. After adding or changing providers, run `terraform init` to update `.terraform.lock.hcl`. For a local plan, bootstrap the state account and authenticate to Azure, then run `terraform init` with the backend values and `terraform plan`. Keep `enable_cosmos_free_tier = true` only if the subscription has no other Cosmos free-tier account. Set `enable_sql_free_tier = false` only if the SQL free offer is unavailable; this can incur charges. `sql_firewall_allowlist` should contain only developer IPv4 addresses needed for local test access.

Azure SQL and Cosmos can use their free allowances, and Functions provides a monthly free grant, but storage transactions/capacity, Key Vault operations, and monitoring ingestion can still be billed. These settings reduce cost; they cannot guarantee a $0 Azure bill. Review live pricing and usage before any apply.

Azure free-tier quotas, regional availability, and consumption-plan limits can change. Review the resulting plan and Azure pricing/quotas before applying.

### Apply the existing Azure SQL schema for the local demo

The schema runner uses the active Azure CLI Entra session and ODBC Driver 17 or 18;
it does not require or print a SQL password or access token. The default target is the
ReconFlow demo SQL server/database. Override it only when intentionally targeting a
different database:

```powershell
$env:RECONFLOW_SQL_SERVER = "your-server.database.windows.net"
$env:RECONFLOW_SQL_DATABASE = "your-database"
az login
python .\scripts\apply_azure_sql_schema.py
```

`AZURE_TENANT_ID` is optional and should be supplied through the local shell only if
the active Azure CLI context needs to be pinned to a tenant. The script splits the
idempotent DDL on `GO`, executes each batch, and verifies all 19 expected base tables.
It creates the schema only; the application is not yet configured to persist requests
or uploads to Azure SQL. Verify the target server/database and expected cost before
running it against any other environment.

## Optional commercial scanners

The `secops` workflow always runs the free Terraform and Trivy checks. Mend OSS/SCA runs only when all of these are configured: repository/organization secrets `MEND_EMAIL` and `MEND_USER_KEY`, and variables `MEND_URL` and `MEND_ORGANIZATION` (organization UUID). Checkmarx AST runs only when `CX_CLIENT_ID` and `CX_CLIENT_SECRET` secrets plus `CX_BASE_URI` and `CX_TENANT` variables are configured. Without a complete credential/configuration set, the corresponding commercial job is skipped. Do not put credentials in variables or workflow files.