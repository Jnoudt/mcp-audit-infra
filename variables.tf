variable "resource_group_name" {
  description = "Existing Azure Resource Group name for MCP Audit resources."
  type        = string
  default     = "rg-mcp-audit-dev"
}

variable "project_name" {
  description = "Short lowercase alphanumeric prefix for resource names (3-10 characters)."
  type        = string
  default     = "mcpaudit"

  validation {
    condition     = can(regex("^[a-z0-9]{3,10}$", var.project_name))
    error_message = "project_name must be 3-10 lowercase alphanumeric characters."
  }
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,10}$", var.environment))
    error_message = "environment must be 2-10 lowercase letters, digits, or hyphens."
  }
}

variable "location" {
  description = "Azure region for provisioned resources."
  type        = string
  default     = "southafricanorth"
}

variable "cosmos_database_name" {
  description = "Cosmos DB SQL database name for MCP audit logs."
  type        = string
  default     = "mcp_audit_db"
}

variable "cosmos_container_name" {
  description = "Cosmos DB container name partitioned by /tenantId."
  type        = string
  default     = "audit_events"
}

variable "foundry_resource_id" {
  description = "Optional resource ID of an existing Foundry account for Function managed-identity inference access."
  type        = string
  default     = ""
}

variable "foundry_openai_base_url" {
  description = "Optional existing Foundry OpenAI v1 endpoint; this is configuration, not a credential."
  type        = string
  default     = ""
}

variable "foundry_model_deployment" {
  description = "Optional name of an already-created Foundry model deployment."
  type        = string
  default     = ""
}

variable "sql_database_name" {
  description = "Azure SQL Database name for ReconFlow relational data."
  type        = string
  default     = "reconflow"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,128}$", var.sql_database_name))
    error_message = "sql_database_name must be 1-128 letters, digits, underscores, or hyphens."
  }
}

variable "sql_administrator_login" {
  description = "Display/login name of the Microsoft Entra administrator for Azure SQL."
  type        = string
}

variable "sql_administrator_object_id" {
  description = "Object ID of the Microsoft Entra administrator for Azure SQL."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.sql_administrator_object_id))
    error_message = "sql_administrator_object_id must be a valid UUID."
  }
}

variable "sql_firewall_allowlist" {
  description = "Public IPv4 addresses allowed to connect to Azure SQL, for local development only."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for ip in var.sql_firewall_allowlist : can(cidrnetmask("${ip}/32"))])
    error_message = "sql_firewall_allowlist entries must be valid IPv4 addresses."
  }
}

variable "enable_sql_free_tier" {
  description = "Use Azure SQL's monthly free limit and pause the database when the limit is exhausted."
  type        = bool
  default     = true
}

variable "function_maximum_instance_count" {
  description = "Maximum Flex Consumption instances for the low-cost development environment."
  type        = number
  default     = 1

  validation {
    condition     = var.function_maximum_instance_count >= 1 && var.function_maximum_instance_count <= 40
    error_message = "function_maximum_instance_count must be between 1 and 40."
  }
}

variable "enable_cosmos_free_tier" {
  description = "Enable only when no other Cosmos DB free-tier account exists in the subscription."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Baseline tags applied across Azure resources."
  type        = map(string)
  default = {
    project             = "mcp-audit-server"
    managed_by          = "terraform"
    owner               = "project-maintainers"
    data_classification = "confidential"
    tier                = "free-tier"
  }
}