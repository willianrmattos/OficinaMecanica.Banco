# So uma referencia por nome ao resource group ja existente (rgfiap, criado
# e gerenciado pelo OficinaMecanica.Infra) - este repo nao cria nem destroi
# esse RG, so cria recursos dentro dele. Extraido do modulo sqldb/ que
# vivia em OficinaMecanica.Infra, sem recriar nada no Azure (terraform
# import dos recursos ja existentes pra esse state novo).
data "azurerm_resource_group" "existing" {
  name = var.resource_group_name
}

resource "azurerm_mssql_server" "this" {
  name                = var.server_name
  resource_group_name = data.azurerm_resource_group.existing.name
  location            = var.location
  version             = "12.0"

  administrator_login          = var.administrator_login
  administrator_login_password = var.administrator_login_password

  minimum_tls_version           = "1.2"
  public_network_access_enabled = true

  tags = var.tags
}

resource "azurerm_mssql_database" "this" {
  name      = var.database_name
  server_id = azurerm_mssql_server.this.id

  collation                   = "SQL_Latin1_General_CP1_CI_AS"
  sku_name                    = var.sku_name
  max_size_gb                 = var.max_size_gb
  min_capacity                = var.min_capacity
  auto_pause_delay_in_minutes = var.auto_pause_delay_in_minutes
  storage_account_type        = "Local"
  zone_redundant              = false

  tags = var.tags
}

# Segundo banco no MESMO servidor logico (nao um servidor novo - evita outro
# risco de regiao/capacidade como o que ja aconteceu na criacao do server
# principal, e reaproveita as mesmas credenciais de administrador). O tier
# sempre-gratis (use_free_limit) so vale 1x por assinatura, ja usado pelo
# banco "this" acima - este aqui e um serverless comum, com custo pequeno
# baseado no uso real (auto-pause reduz isso ao minimo).
resource "azurerm_mssql_database" "seguranca" {
  name      = var.seguranca_database_name
  server_id = azurerm_mssql_server.this.id

  collation                   = "SQL_Latin1_General_CP1_CI_AS"
  sku_name                    = var.seguranca_sku_name
  max_size_gb                 = var.seguranca_max_size_gb
  min_capacity                = var.seguranca_min_capacity
  auto_pause_delay_in_minutes = var.seguranca_auto_pause_delay_in_minutes
  storage_account_type        = "Local"
  zone_redundant              = false

  tags = var.tags
}

# Usei a faixa especial 0.0.0.0-0.0.0.0: e o valor que o Azure reconhece como
# "permitir servicos Azure" (ex: pods do AKS), nao libera a internet toda.
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAllWindowsAzureIps"
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_firewall_rule" "client_ip" {
  count            = var.client_ip_address != null ? 1 : 0
  name             = "ClientIp"
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = var.client_ip_address
  end_ip_address   = var.client_ip_address
}
