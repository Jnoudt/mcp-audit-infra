data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  unique_id   = "${var.project_name}${var.environment}${random_string.suffix.result}"

  storage_name          = substr("st${local.unique_id}", 0, 24)
  evidence_storage_name = substr("ev${local.unique_id}", 0, 24)
  key_vault_name = substr(
    "kv-${var.project_name}-${var.environment}-${random_string.suffix.result}",
    0,
    24
  )
  cosmos_name     = "cosmos-${local.name_prefix}-${random_string.suffix.result}"
  sql_server_name = "sql-${local.unique_id}"
  plan_name       = "plan-${local.name_prefix}-${random_string.suffix.result}"
  func_name       = "func-${local.name_prefix}-${random_string.suffix.result}"
  law_name        = "law-${local.name_prefix}-${random_string.suffix.result}"
  appi_name       = "appi-${local.name_prefix}-${random_string.suffix.result}"

  merged_tags = merge(var.tags, {
    environment = var.environment
  })
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = local.law_name
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.merged_tags
}

resource "azurerm_application_insights" "main" {
  name                = local.appi_name
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = local.merged_tags
}

resource "azurerm_storage_account" "func" {
  name                     = local.storage_name
  resource_group_name      = data.azurerm_resource_group.main.name
  location                 = data.azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false

  tags = local.merged_tags
}

resource "azurerm_storage_account" "evidence" {
  name                     = local.evidence_storage_name
  resource_group_name      = data.azurerm_resource_group.main.name
  location                 = data.azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false
  shared_access_key_enabled        = false
  cross_tenant_replication_enabled = false

  tags = local.merged_tags
}

resource "azurerm_storage_container" "evidence_documents" {
  name                  = "documents"
  storage_account_id    = azurerm_storage_account.evidence.id
  container_access_type = "private"

  depends_on = [azurerm_role_assignment.deployer_evidence_blob_data_contributor]
}

resource "azurerm_service_plan" "flex" {
  name                = local.plan_name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "FC1"
  tags                = local.merged_tags
}

resource "azurerm_cosmosdb_account" "audit" {
  name                         = local.cosmos_name
  location                     = data.azurerm_resource_group.main.location
  resource_group_name          = data.azurerm_resource_group.main.name
  offer_type                   = "Standard"
  kind                         = "GlobalDocumentDB"
  free_tier_enabled            = var.enable_cosmos_free_tier
  local_authentication_enabled = false

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = data.azurerm_resource_group.main.location
    failover_priority = 0
  }

  tags = local.merged_tags
}

resource "azurerm_cosmosdb_sql_database" "audit" {
  name                = var.cosmos_database_name
  resource_group_name = data.azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.audit.name
}

resource "azurerm_cosmosdb_sql_container" "audit_events" {
  name                  = var.cosmos_container_name
  resource_group_name   = data.azurerm_resource_group.main.name
  account_name          = azurerm_cosmosdb_account.audit.name
  database_name         = azurerm_cosmosdb_sql_database.audit.name
  partition_key_paths   = ["/tenantId"]
  partition_key_version = 2
  throughput            = 400

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }

    excluded_path {
      path = "/\"_etag\"/?"
    }
  }
}

resource "azurerm_mssql_server" "relational" {
  name                          = local.sql_server_name
  resource_group_name           = data.azurerm_resource_group.main.name
  location                      = data.azurerm_resource_group.main.location
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = true

  azuread_administrator {
    login_username              = var.sql_administrator_login
    object_id                   = var.sql_administrator_object_id
    tenant_id                   = data.azurerm_client_config.current.tenant_id
    azuread_authentication_only = true
  }

  tags = local.merged_tags
}

resource "azurerm_mssql_firewall_rule" "local_test" {
  for_each = toset(var.sql_firewall_allowlist)

  name             = "local-${replace(each.value, ".", "-")}"
  server_id        = azurerm_mssql_server.relational.id
  start_ip_address = each.value
  end_ip_address   = each.value
}

# AzureRM does not expose the SQL free-limit properties. AutoPause avoids paid
# overage after the monthly free allowance; subscription eligibility still applies.
resource "azapi_resource" "relational_database" {
  type      = "Microsoft.Sql/servers/databases@2023-08-01"
  parent_id = azurerm_mssql_server.relational.id
  name      = var.sql_database_name
  location  = data.azurerm_resource_group.main.location

  body = {
    properties = {
      autoPauseDelay                   = 60
      collation                        = "SQL_Latin1_General_CP1_CI_AS"
      createMode                       = "Default"
      freeLimitExhaustionBehavior      = "AutoPause"
      licenseType                      = "LicenseIncluded"
      maxSizeBytes                     = 34359738368
      requestedBackupStorageRedundancy = "Local"
      useFreeLimit                     = var.enable_sql_free_tier
    }
    sku = {
      capacity = 2
      family   = "Gen5"
      name     = "GP_S_Gen5_2"
      tier     = "GeneralPurpose"
    }
  }

  tags = local.merged_tags
}

resource "azurerm_storage_container" "deployment" {
  name                  = "deploymentpackage"
  storage_account_id    = azurerm_storage_account.func.id
  container_access_type = "private"

  depends_on = [azurerm_role_assignment.deployer_storage_blob_data_contributor]
}

resource "azurerm_key_vault" "main" {
  name                       = local.key_vault_name
  location                   = data.azurerm_resource_group.main.location
  resource_group_name        = data.azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = true

  tags = local.merged_tags
}

resource "azurerm_function_app_flex_consumption" "mcp_server" {
  name                = local.func_name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.flex.id

  storage_container_type      = "blobContainer"
  storage_container_endpoint  = "${azurerm_storage_account.func.primary_blob_endpoint}${azurerm_storage_container.deployment.name}"
  storage_authentication_type = "SystemAssignedIdentity"
  runtime_name                = "python"
  runtime_version             = "3.12"
  maximum_instance_count      = var.function_maximum_instance_count
  instance_memory_in_mb       = 2048
  https_only                  = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_insights_connection_string = azurerm_application_insights.main.connection_string
  }

  app_settings = {
    # Flex Consumption requires this compatibility setting. Host storage
    # authentication uses the account-name identity setting below.
    AzureWebJobsStorage              = ""
    AzureWebJobsStorage__accountName = azurerm_storage_account.func.name
    COSMOS_ENDPOINT                  = azurerm_cosmosdb_account.audit.endpoint
    COSMOS_DATABASE_NAME             = azurerm_cosmosdb_sql_database.audit.name
    COSMOS_CONTAINER_NAME            = azurerm_cosmosdb_sql_container.audit_events.name
    SQL_SERVER_FQDN                  = azurerm_mssql_server.relational.fully_qualified_domain_name
    SQL_DATABASE_NAME                = azapi_resource.relational_database.name
    SQL_AUTHENTICATION_MODE          = "ActiveDirectoryManagedIdentity"
    DOCUMENT_STORAGE_ACCOUNT_NAME    = azurerm_storage_account.evidence.name
    DOCUMENT_STORAGE_CONTAINER_NAME  = azurerm_storage_container.evidence_documents.name
    KEY_VAULT_URI                    = azurerm_key_vault.main.vault_uri
    FOUNDRY_OPENAI_BASE_URL          = var.foundry_openai_base_url
    FOUNDRY_MODEL_DEPLOYMENT         = var.foundry_model_deployment
    FOUNDRY_REASONING_EFFORT         = "low"
    RECONFLOW_AI_ENABLED             = "false"
    ENVIRONMENT                      = var.environment
  }

  tags = local.merged_tags
}

resource "azurerm_role_assignment" "func_foundry_openai_user" {
  count = var.foundry_resource_id == "" ? 0 : 1

  scope                = var.foundry_resource_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_function_app_flex_consumption.mcp_server.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "func_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_function_app_flex_consumption.mcp_server.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "deployer_kv_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_cosmosdb_sql_role_assignment" "func_cosmos_data_contributor" {
  resource_group_name = data.azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.audit.name
  role_definition_id  = "${azurerm_cosmosdb_account.audit.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azurerm_function_app_flex_consumption.mcp_server.identity[0].principal_id
  scope               = azurerm_cosmosdb_account.audit.id
}

resource "azurerm_role_assignment" "func_storage_blob_data_owner" {
  scope                = azurerm_storage_account.func.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_function_app_flex_consumption.mcp_server.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "deployer_storage_blob_data_contributor" {
  scope                = azurerm_storage_account.func.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "func_evidence_blob_data_contributor" {
  scope                = azurerm_storage_account.evidence.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_function_app_flex_consumption.mcp_server.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "deployer_evidence_blob_data_contributor" {
  scope                = azurerm_storage_account.evidence.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = "ServicePrincipal"
}