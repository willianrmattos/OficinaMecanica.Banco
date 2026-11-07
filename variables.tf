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

variable "key_vault_name" {
  description = "Nome do Key Vault ja existente (kvfiap, criado pelo OficinaMecanica.Infra) onde este repositorio grava a connection string do MongoDB Atlas do Execucao - so uma referencia por nome (data source). No CI, o github_oidc_banco precisa da role 'Key Vault Secrets Officer' escopada ao secret (concedida pelo Infra), senao o azurerm_key_vault_secret falha com 403; o primeiro apply e local, com um administrador do Key Vault."
  type        = string
  default     = "kvfiap"
}

variable "atlas_org_id" {
  description = "ID da organizacao do MongoDB Atlas (24 caracteres hexadecimais, em Organization Settings) onde o projeto e criado. Sem valor padrao: definir via TF_VAR_atlas_org_id. As credenciais da API do Atlas NAO sao variaveis: o provider le MONGODB_ATLAS_PUBLIC_KEY e MONGODB_ATLAS_PRIVATE_KEY do ambiente."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{24}$", var.atlas_org_id))
    error_message = "atlas_org_id deve ter 24 caracteres hexadecimais minusculos (ID da organizacao no Atlas)."
  }
}

variable "atlas_project_name" {
  description = "Nome do projeto do Atlas criado por este repositorio. Projeto proprio (nao compartilhado) porque o limite do M0 e de 1 cluster gratuito por projeto e porque usuarios, IP access list e API keys do Atlas sao escopados por projeto."
  type        = string
  default     = "OficinaMecanica"
}

variable "atlas_cluster_name" {
  description = "Nome do cluster M0 gratuito do Execucao no Atlas (letras, digitos e hifens). Um cluster M0 nao pode ser modificado depois de criado, entao trocar o nome recria o cluster e perde os dados."
  type        = string
  default     = "execucao"
}

variable "atlas_region" {
  description = "Regiao do cluster M0 no Atlas, no formato do Atlas para provedor AZURE (ex: US_EAST_2 = Virginia, CANADA_CENTRAL = Toronto). Nem toda regiao do Azure oferece o tier gratuito: confirmar na coluna 'Free' da tabela de regioes Azure da documentacao do Atlas antes do apply. Trocar a regiao recria o cluster (M0 nao e modificavel) e perde os dados."
  type        = string
  default     = "US_EAST_2"
}

variable "execucao_mongo_database_name" {
  description = "Nome do banco MongoDB do Execucao. O usuario de banco do Atlas recebe readWrite somente nele, e a aplicacao le o mesmo nome em MongoDb:Database (o padrao do codigo tambem e 'execucao')."
  type        = string
  default     = "execucao"
}

variable "execucao_mongo_username" {
  description = "Usuario de banco do Atlas dedicado ao Execucao (role readWrite somente no banco execucao, nunca atlasAdmin). A senha e gerada pelo Terraform (random_password) e so existe no state e no Key Vault."
  type        = string
  default     = "execucao_app"
}

variable "execucao_mongo_secret_name" {
  description = "Nome do secret no Key Vault que recebe a connection string do MongoDB do Execucao. O OficinaMecanica.Infra referencia esse nome exato (SecretProviderClass do Execucao), entao so mudar aqui junto com o Infra."
  type        = string
  default     = "execucao-mongo-connection-string"
}

variable "aks_egress_ip" {
  description = "IP publico de SAIDA do cluster AKS (aksfiap), unica origem liberada na IP access list do Atlas (/32, nunca 0.0.0.0/0). Sem valor padrao: definir via TF_VAR_aks_egress_ip. Se o cluster for recriado ou o load balancer de saida mudar, o IP muda e os pods perdem acesso ao Mongo (timeout de selecao de servidor) ate este valor ser atualizado e o apply rodar de novo."
  type        = string

  # A primeira regex exige quatro octetos sem zero a esquerda (a segunda compara o
  # texto, e "010.0.0.1" escaparia dela). A segunda recusa o que nunca e origem
  # publica de saida: 0/8, 10/8, 100.64/10 (CGNAT), 127/8, 169.254/16, 172.16/12,
  # 192.168/16 e 224.0.0.0 em diante (multicast e reservado).
  validation {
    condition = (
      can(cidrnetmask("${var.aks_egress_ip}/32")) &&
      can(regex("^(0|[1-9][0-9]{0,2})(\\.(0|[1-9][0-9]{0,2})){3}$", var.aks_egress_ip)) &&
      !can(regex("^(0|10|127|22[4-9]|2[3-5][0-9])\\.|^100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.|^169\\.254\\.|^172\\.(1[6-9]|2[0-9]|3[01])\\.|^192\\.168\\.", var.aks_egress_ip))
    )
    error_message = "aks_egress_ip deve ser um unico IPv4 valido de origem publica (ex: 203.0.113.10): sem CIDR, sem 0.0.0.0 e sem faixas privadas, loopback, link-local, CGNAT, multicast ou reservadas."
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
