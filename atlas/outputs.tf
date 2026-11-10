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
