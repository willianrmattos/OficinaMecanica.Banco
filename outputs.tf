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
