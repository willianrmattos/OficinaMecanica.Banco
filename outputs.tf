output "server_name" {
  description = "Nome do SQL Server criado."
  value       = azurerm_mssql_server.this.name
}

output "server_fqdn" {
  description = "Endereco completo do servidor (usar na connection string, ex: Server=<valor>,1433)."
  value       = azurerm_mssql_server.this.fully_qualified_domain_name
}

output "database_name" {
  description = "Nome do banco de dados do monolito OficinaMecanica."
  value       = azurerm_mssql_database.this.name
}

output "seguranca_database_name" {
  description = "Nome do banco de dados do servico OficinaMecanica.Seguranca."
  value       = azurerm_mssql_database.seguranca.name
}
