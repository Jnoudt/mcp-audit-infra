output "resource_group_name" {
  description = "Provisioned Azure Resource Group name."
  value       = azurerm_resource_group.main.name
}

output "function_app_name" {
  description = "Target Function App name for application deployments."
  value       = azurerm_function_app_flex_consumption.mcp_server.name
}

output "function_app_default_hostname" {
  description = "Default HTTPS hostname of the MCP Function App."
  value       = azurerm_function_app_flex_consumption.mcp_server.default_hostname
}

output "function_app_principal_id" {
  description = "System-Assigned Managed Identity Principal ID of the Function App."
  value       = azurerm_function_app_flex_consumption.mcp_server.identity[0].principal_id
}

output "cosmos_db_endpoint" {
  description = "Azure Cosmos DB SQL API endpoint."
  value       = azurerm_cosmosdb_account.audit.endpoint
}

output "cosmos_db_database_name" {
  description = "Cosmos DB SQL database name."
  value       = azurerm_cosmosdb_sql_database.audit.name
}

output "cosmos_db_container_name" {
  description = "Cosmos DB SQL container name."
  value       = azurerm_cosmosdb_sql_container.audit_events.name
}

output "key_vault_uri" {
  description = "Azure Key Vault URI."
  value       = azurerm_key_vault.main.vault_uri
}

output "application_insights_app_id" {
  description = "Application Insights App ID."
  value       = azurerm_application_insights.main.app_id
}