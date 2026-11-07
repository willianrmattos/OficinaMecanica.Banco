output "resource_group_name" {
  description = "Nome do resource group onde o SQL Server existe (rgfiap). Usado pelo CI pra abrir/fechar a regra temporaria de firewall do runner."
  value       = data.azurerm_resource_group.existing.name
}

output "server_name" {
  description = "Nome do SQL Server criado."
  value       = azurerm_mssql_server.this.name
}

output "server_fqdn" {
  description = "Endereco completo do servidor (usar na connection string, ex: Server=<valor>,1433)."
  value       = azurerm_mssql_server.this.fully_qualified_domain_name
}

output "administrator_login" {
  description = "Login do administrador do SQL Server (a senha e sensivel e nunca sai como output). Usado pelo CI so pra criar os usuarios contidos por banco."
  value       = azurerm_mssql_server.this.administrator_login
}

output "database_name" {
  description = "Nome do banco de dados do monolito OficinaMecanica."
  value       = azurerm_mssql_database.this.name
}

output "seguranca_database_name" {
  description = "Nome do banco de dados do servico OficinaMecanica.Seguranca."
  value       = azurerm_mssql_database.seguranca.name
}

output "billing_database_name" {
  description = "Nome do banco de dados do servico OficinaMecanica.Billing."
  value       = azurerm_mssql_database.billing.name
}

output "atlas_project_id" {
  description = "ID do projeto do MongoDB Atlas criado para o Execucao."
  value       = mongodbatlas_project.this.id
}

output "atlas_cluster_name" {
  description = "Nome do cluster M0 do Execucao no Atlas."
  value       = mongodbatlas_advanced_cluster.execucao.name
}

output "atlas_cluster_srv_host" {
  description = "Host SRV do cluster (sem credenciais), ex: <cluster>.<id>.mongodb.net. A connection string completa, com usuario e senha, so existe no Key Vault (e no state) - nao e exposta como output."
  value       = local.execucao_mongo_srv_host
}

output "execucao_mongo_database_name" {
  description = "Nome do banco MongoDB do Execucao (usuario do Atlas tem readWrite so nele)."
  value       = var.execucao_mongo_database_name
}

output "execucao_mongo_username" {
  description = "Usuario de banco do Atlas dedicado ao Execucao."
  value       = mongodbatlas_database_user.execucao_app.username
}

output "execucao_mongo_secret_name" {
  description = "Nome do secret no Key Vault que guarda a connection string do MongoDB do Execucao (o valor nao e exposto aqui)."
  value       = azurerm_key_vault_secret.execucao_mongo_connection_string.name
}
