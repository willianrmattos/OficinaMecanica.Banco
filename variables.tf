variable "location" {
  description = "Regiao do Azure onde o SQL Server sera criado. Independente da regiao do resource group (SQL Database e publico, nao requer VNet/peering para ser alcancado)."
  type        = string
  default     = "canadacentral"
}

variable "resource_group_name" {
  description = "Nome do resource group ja existente (rgfiap, criado pelo OficinaMecanica.Infra) onde o SQL Server sera criado - so uma referencia por nome (data source), este repo nao cria nem gerencia o resource group."
  type        = string
  default     = "rgfiap"
}

variable "server_name" {
  description = "Nome do SQL Server (logico). Globalmente unico - vira <nome>.database.windows.net."
  type        = string
  default     = "svsfiap"
}

variable "database_name" {
  description = "Nome do banco de dados do monolito OficinaMecanica."
  type        = string
  default     = "OficinaMecanicaDb"
}

variable "administrator_login" {
  description = "Usuario administrador do SQL Server."
  type        = string
  default     = "adminfiap"
}

variable "administrator_login_password" {
  description = "Senha do administrador do SQL Server. Sem valor padrao: definir via TF_VAR_administrator_login_password ou um .tfvars nao versionado."
  type        = string
  sensitive   = true
}

variable "sku_name" {
  description = "SKU do banco. GP_S_Gen5_2 = General Purpose Serverless, Gen5, ate 2 vCores."
  type        = string
  default     = "GP_S_Gen5_2"
}

variable "max_size_gb" {
  description = "Tamanho maximo do banco em GB (32GB corresponde ao limite do tier sempre-gratis do Azure SQL Database)."
  type        = number
  default     = 32
}

variable "min_capacity" {
  description = "Capacidade minima (vCores) quando o banco nao esta pausado (serverless)."
  type        = number
  default     = 0.5
}

variable "auto_pause_delay_in_minutes" {
  description = "Minutos de inatividade antes do banco pausar automaticamente (serverless)."
  type        = number
  default     = 60
}

variable "seguranca_database_name" {
  description = "Nome do banco de dados do servico OficinaMecanica.Seguranca (segundo banco, mesmo servidor)."
  type        = string
  default     = "SegurancaDb"
}

variable "seguranca_sku_name" {
  description = "SKU do banco do Seguranca. Mesma familia serverless do banco principal, sem qualificar pro tier sempre-gratis (ja usado)."
  type        = string
  default     = "GP_S_Gen5_2"
}

variable "seguranca_max_size_gb" {
  description = "Tamanho maximo do banco do Seguranca em GB - bem menor que o principal, o dominio (so Usuario) e minusculo."
  type        = number
  default     = 2
}

variable "seguranca_min_capacity" {
  description = "Capacidade minima (vCores) do banco do Seguranca quando nao pausado."
  type        = number
  default     = 0.5
}

variable "seguranca_auto_pause_delay_in_minutes" {
  description = "Minutos de inatividade antes do banco do Seguranca pausar automaticamente."
  type        = number
  default     = 60
}

variable "client_ip_address" {
  description = "IP publico autorizado a acessar o banco diretamente (execucao de migrations, conexao via SSMS/Azure Data Studio). Null nao libera nenhum IP especifico, apenas servicos Azure."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags aplicadas aos recursos."
  type        = map(string)
  default     = {}
}
