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

variable "billing_database_name" {
  description = "Nome do banco de dados do servico OficinaMecanica.Billing (terceiro banco, mesmo servidor)."
  type        = string
  default     = "BillingDb"
}

variable "billing_sku_name" {
  description = "SKU do banco do Billing. Mesma familia serverless do Seguranca, sem qualificar pro tier sempre-gratis (ja usado pelo banco do monolito)."
  type        = string
  default     = "GP_S_Gen5_2"
}

variable "billing_max_size_gb" {
  description = "Tamanho maximo do banco do Billing em GB. Maior que o do Seguranca porque orcamentos, pagamentos, webhooks recebidos e as tabelas de outbox/inbox crescem a cada ordem de servico; e so um teto, o custo segue o espaco realmente usado."
  type        = number
  default     = 5
}

variable "billing_min_capacity" {
  description = "Capacidade minima (vCores) do banco do Billing quando nao pausado."
  type        = number
  default     = 0.5
}

variable "billing_auto_pause_delay_in_minutes" {
  description = "Minutos de inatividade antes do banco do Billing pausar automaticamente."
  type        = number
  default     = 60
}

# Os tres usuarios SQL contidos (app_os, app_seguranca, app_billing) NAO sao
# criados pelo Terraform - o provider azurerm nao cria usuario contido de
# Azure SQL. Quem cria e o sql/criar-usuarios.sql, no job apply do CI. Declarei
# as senhas aqui mesmo assim, com os mesmos nomes que o OficinaMecanica.Infra
# usa pra montar as connection strings no Key Vault, por um motivo pratico: o
# "validation" abaixo faz o plan (que roda antes do apply, tambem em PR)
# falhar cedo se o secret estiver ausente ou fora do padrao, em vez de o apply
# terminar e so depois o passo de SQL descobrir que nao da pra criar o usuario.
# O padrao de caracteres exclui aspas, ponto e virgula, igual e barra
# invertida: essas senhas entram num literal T-SQL e numa connection string.
variable "sql_app_os_password" {
  description = "Senha do usuario SQL contido app_os (db_owner so em OficinaMecanicaDb), usado pelo OficinaMecanica. Sem valor padrao: definir via TF_VAR_sql_app_os_password. 16 a 128 caracteres entre letras, digitos e _ . @ # % ^ * + ~ -, com maiuscula, minuscula e digito. Nao e consumida por nenhum recurso deste repositorio - ver o comentario acima."
  type        = string
  sensitive   = true

  validation {
    condition = (
      can(regex("^[A-Za-z0-9_.@#%^*+~-]{16,128}$", var.sql_app_os_password)) &&
      can(regex("[A-Z]", var.sql_app_os_password)) &&
      can(regex("[a-z]", var.sql_app_os_password)) &&
      can(regex("[0-9]", var.sql_app_os_password))
    )
    error_message = "sql_app_os_password deve ter 16 a 128 caracteres entre letras, digitos e _ . @ # % ^ * + ~ - (sem aspas, ponto e virgula, igual, espaco ou barra invertida), com ao menos uma maiuscula, uma minuscula e um digito."
  }
}

variable "sql_app_seguranca_password" {
  description = "Senha do usuario SQL contido app_seguranca (db_owner so em SegurancaDb), usado pelo OficinaMecanica.Seguranca. Sem valor padrao: definir via TF_VAR_sql_app_seguranca_password. Mesmo padrao de caracteres de sql_app_os_password."
  type        = string
  sensitive   = true

  validation {
    condition = (
      can(regex("^[A-Za-z0-9_.@#%^*+~-]{16,128}$", var.sql_app_seguranca_password)) &&
      can(regex("[A-Z]", var.sql_app_seguranca_password)) &&
      can(regex("[a-z]", var.sql_app_seguranca_password)) &&
      can(regex("[0-9]", var.sql_app_seguranca_password))
    )
    error_message = "sql_app_seguranca_password deve ter 16 a 128 caracteres entre letras, digitos e _ . @ # % ^ * + ~ - (sem aspas, ponto e virgula, igual, espaco ou barra invertida), com ao menos uma maiuscula, uma minuscula e um digito."
  }
}

variable "sql_app_billing_password" {
  description = "Senha do usuario SQL contido app_billing (db_owner so em BillingDb), usado pelo OficinaMecanica.Billing. Sem valor padrao: definir via TF_VAR_sql_app_billing_password. Mesmo padrao de caracteres de sql_app_os_password."
  type        = string
  sensitive   = true

  validation {
    condition = (
      can(regex("^[A-Za-z0-9_.@#%^*+~-]{16,128}$", var.sql_app_billing_password)) &&
      can(regex("[A-Z]", var.sql_app_billing_password)) &&
      can(regex("[a-z]", var.sql_app_billing_password)) &&
      can(regex("[0-9]", var.sql_app_billing_password))
    )
    error_message = "sql_app_billing_password deve ter 16 a 128 caracteres entre letras, digitos e _ . @ # % ^ * + ~ - (sem aspas, ponto e virgula, igual, espaco ou barra invertida), com ao menos uma maiuscula, uma minuscula e um digito."
  }
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
