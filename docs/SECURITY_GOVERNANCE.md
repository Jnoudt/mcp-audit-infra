# Security and Governance Policy

**Status:** Baseline policy for the `mcp-audit-infra` and `mcp-audit-server` repositories  
**Applies to:** Source code, CI/CD, Terraform-managed Azure resources, MCP tool requests, and audit data

This policy establishes minimum security and governance controls. A passing CI scan is evidence of checks performed, not proof that a system is secure. Exceptions must be documented, risk-assessed, time-bounded, and approved by the project owner.

## 1. Resource governance and tagging

- Apply the baseline tags to every supported Azure resource, including resources created indirectly where the provider permits tagging:
  - `project`: stable project identifier (`mcp-audit-server`)
  - `environment`: approved environment name (`dev`, `staging`, or `prod`)
  - `managed_by`: `terraform`
  - `owner`: accountable team or role (use a non-personal team identifier)
  - `cost_center`: approved cost allocation value, when one is available
  - `data_classification`: highest classification of data the resource may hold
- Keep tag names and values lowercase and use an approved, finite vocabulary. Do not put credentials, personal data, tenant identifiers, or other sensitive values in tags, resource names, or diagnostic metadata.
- CI must run Terraform formatting and validation and review plans before changes are applied. Production changes require protected branches and an approval gate. Detect and investigate unreviewed drift; do not automatically overwrite a security-relevant change without review.
- Pin supported tool/provider version ranges and review dependency/provider release notes before upgrades. Avoid unbounded versions and deprecated resource types or properties.

## 2. Identity, RBAC, and secrets

- Use system-assigned managed identity for the Function App's runtime access to Azure services. Prefer Microsoft Entra ID and data-plane RBAC over account keys, connection strings containing credentials, or shared secrets.
- Grant only the roles and scopes required for a task. Scope Cosmos DB data roles to the required account/database/container where supported; scope Key Vault roles to the vault. Do not grant the application subscription-wide or resource-group-wide contributor/owner roles.
- Separate deployment identity from runtime identity. GitHub Actions authenticates with workload identity federation/OIDC (`azure/login@v2`); do not create or store long-lived Azure client secrets. The CI identity must have only the control-plane and role-assignment permissions needed for the reviewed deployment, at the narrowest practical scope.
- Keep Terraform state in a dedicated, access-controlled storage account using Entra/OIDC authentication. State may contain sensitive values: restrict read access, enable appropriate storage protections, never commit state/plan files, and do not publish them as broadly accessible artifacts.
- Store application secrets in Key Vault only when a secret is unavoidable. Never hardcode secrets in code, Terraform variables/defaults, workflow YAML, logs, test fixtures, or repository history. Rotate and revoke exposed credentials promptly.
- Review role assignments periodically and remove unused identities and privileges. Treat role-assignment creation as privileged deployment activity.

## 3. MCP tool input and execution threat mitigations

The server must treat every tool argument, resource identifier, tenant value, and upstream response as untrusted, even when supplied by an authenticated client.

- Validate requests at the boundary with strict Pydantic v2 schemas: reject unknown or malformed fields, enforce types, lengths, ranges, formats, and enumerations, and reject non-finite numeric values. Do not coerce ambiguous input into a different meaning.
- Bind every data operation to the authenticated tenant/principal on the server side. Never trust a caller-provided tenant or authorization claim without verifying it. Enforce authorization for each tool invocation and resource access; deny by default.
- Use allowlists for tool names, operations, and external destinations. Prevent path traversal, server-side request forgery, injection into queries/commands, unsafe URL fetching, and access to metadata services or internal networks. Do not execute caller-supplied code, shell commands, or arbitrary query fragments.
- Perform financial, tax, and compliance calculations deterministically with decimal arithmetic and explicit rules. Do not use LLM output as an authority for validation, authorization, calculations, or compliance decisions.
- Apply request size, item-count, nesting-depth, timeout, and rate limits. Fail closed on schema, authorization, and policy errors. Return stable, structured MCP/JSON-RPC errors without stack traces, infrastructure identifiers, secrets, or internal exception text.
- Use bounded retries with exponential backoff and jitter only for retryable transient failures. Make writes idempotent where possible, and use a correlation `trace_id` to associate an operation's request, result, and logs without using it as an authorization token.
- Protect data in transit with TLS. Use managed identity and least-privilege RBAC for Cosmos DB and Key Vault. Avoid secrets in application settings when identity-based access is supported.

## 4. Audit logs and observability

- Emit structured JSON logs with consistent event names, severity, timestamps, and a generated correlation `trace_id`. Keep log fields typed and bounded; do not interpolate untrusted values into log templates or treat user text as a format string.
- Record security-relevant outcomes (for example, authenticated principal reference, authorized tool/action, decision, result status, and trace ID) while minimizing collected data. Do not log access tokens, keys, credentials, full request bodies by default, or unnecessary personal, financial, or sensitive tenant data.
- Sanitize or encode user-controlled log fields to prevent control-character and newline log forging. Apply retention and access controls appropriate to the data classification. Restrict production log access and audit access to the logs themselves.
- Ensure error responses are safe for clients; detailed exceptions belong only in access-controlled telemetry and must still be redacted. Configure telemetry exporters so secrets and sensitive payloads are not captured by automatic dependency/request collection.

## 5. Dependency, platform, and version currency

Maintain and periodically review a supported-version matrix. CI should detect unsupported/outdated pins and deprecated Azure configuration; findings must be triaged and resolved or recorded as approved, time-bounded exceptions.

- **Python:** target Python **3.12** for the application and test/scan environments, subject to the selected Azure Functions runtime and hosting plan supporting it. Keep CI, local tooling, dependency metadata, and the deployed Function App stack aligned. The infrastructure now configures Python 3.12 on Flex Consumption.
- **Terraform CLI:** require **Terraform >= 1.8.0** and pin CI to a reviewed version that satisfies that minimum. The workflow currently pins Terraform **1.17.2**. Run `terraform fmt -check` and `terraform validate` against the committed provider lock file.
- **AzureRM provider:** use **azurerm v4** with a bounded, reviewed version constraint; the current `providers.tf` constraint is `~> 4.14`. The lock file selects **4.81.0**, the latest v4 release available from the Registry as of this review. Commit `.terraform.lock.hcl` and review provider upgrades. The `random` provider has its separate `~> 3.6` constraint and is locked at 3.9.1.
- **Azure resources:** use supported resource types and runtimes. Review Azure Functions hosting/runtime support, regional availability, quotas, and lifecycle notices before deployment. Do not introduce deprecated SKUs or resource types. Linux Consumption `Y1` is a legacy plan scheduled for retirement on September 30, 2028; this infrastructure uses the recommended Linux Flex Consumption `FC1` plan instead. Reassess free-tier eligibility and costs because Azure quotas and pricing can change.
- **Dependencies and actions:** pin or constrain dependencies to supported releases, review advisories and deprecations, and update stale GitHub Actions to maintained versions. Prefer immutable action commit SHAs for high-assurance workflows where operationally practical.

## 6. Verification and exceptions

- Pull requests should run formatting, static analysis, dependency/vulnerability checks, infrastructure validation, and relevant unit/security tests before merge.
- The `secops` workflow always runs the free Terraform/Trivy checks. Optional Mend SCA and Checkmarx scans run only when their complete secret/variable sets are available; forked pull requests without secrets skip those jobs.
- Review scanner findings for exploitability and context; do not silently suppress failures. Document suppressions with rationale, owner, expiry/review date, and a narrow rule or package scope.
- The current Trivy scan reports critical default-network-access findings for the Function Storage Account (`AZU-0012`) and Key Vault (`AZU-0013`). These are intentionally not suppressed. Design and validate network restrictions together with Function egress and GitHub deployment access before declaring the IaC security scan clean.
- Review this policy at least annually and after material changes to Azure architecture, MCP tool capabilities, data classification, or supported platform versions.
