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