# Remote MCP Tool Server — Infrastructure

Terraform infrastructure for the Remote MCP Tool Server's domain and audit workflows. The application code is maintained separately in `mcp-audit-server`.

## Provisioned resources

- Azure Resource Group, Linux Flex Consumption (FC1) Function App, and runtime/deployment Storage Account
- Cosmos DB SQL API account/database/container with a system-assigned identity data-plane role
- Azure Key Vault using Azure RBAC, plus a system-assigned identity secrets-reader role
- Log Analytics workspace and workspace-based Application Insights
- GitHub Actions plan/apply workflow authenticated with Azure OIDC

The Function App uses Flex Consumption (FC1), the current Linux serverless plan. The legacy Linux Consumption (Y1) plan is scheduled to retire on September 30, 2028. Flex Consumption includes monthly free grants, but usage beyond those grants is billed; validate current Azure pricing and quotas before deployment. Python 3.12 is selected for the Function App.

The Cosmos DB account uses provisioned throughput because Cosmos DB free tier is not compatible with serverless mode. The container starts at 400 RU/s; `enable_cosmos_free_tier` is enabled by default and requires that no other free-tier account exists in the subscription. Free-tier eligibility and regional availability are controlled by Azure and are not guaranteed by Terraform.

## Bootstrap and deploy

1. Create a dedicated Azure Storage Account and blob container for Terraform state. This bootstrap storage is intentionally not managed by this state.
2. Grant the GitHub OIDC identity `Storage Blob Data Contributor` on the state container, and sufficient Azure permissions to create the resources and role assignments in the target subscription/resource group. The workflow identity also needs `Storage Blob Data Contributor` on the runtime storage account; Terraform grants this role to the authenticated deployer so it can manage the private deployment container using Entra ID.
3. Configure the GitHub `dev` environment with secrets `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID`; add variables `TF_STATE_RG`, `TF_STATE_SA`, and `TF_STATE_CONTAINER`.
4. Configure an Azure federated identity credential for this repository's GitHub `dev` environment. Do not create client secrets.
5. Run the workflow manually with `plan` first. Merges/pushes to `main` apply the plan; protect `main` and configure required reviewers for the `dev` environment before enabling deployments.

The state backend uses Azure AD/OIDC authentication, so no storage account key is needed for Terraform state access. The Function App uses managed identity for host and deployment storage. Terraform state can still contain sensitive provider attributes and must be access-controlled and never committed.

## Local use

Run the local IaC checks with `pwsh ./scripts/check-iac.ps1`. They require Terraform and Trivy. For a local plan, bootstrap the state account and authenticate to Azure, then run `terraform init` with the backend values and `terraform plan`. Set `enable_cosmos_free_tier = false` if another Cosmos DB account in the subscription already uses the free tier.

Azure free-tier quotas, regional availability, and consumption-plan limits can change. Review the resulting plan and Azure pricing/quotas before applying.

## Optional commercial scanners

The `secops` workflow always runs the free Terraform and Trivy checks. Mend OSS/SCA runs only when all of these are configured: repository/organization secrets `MEND_EMAIL` and `MEND_USER_KEY`, and variables `MEND_URL` and `MEND_ORGANIZATION` (organization UUID). Checkmarx AST runs only when `CX_CLIENT_ID` and `CX_CLIENT_SECRET` secrets plus `CX_BASE_URI` and `CX_TENANT` variables are configured. Without a complete credential/configuration set, the corresponding commercial job is skipped. Do not put credentials in variables or workflow files.