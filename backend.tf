# Mesma storage account/container do tfstate do OficinaMecanica.Infra
# (reaproveitado, nao criei um novo so pra esse repo) - key diferente
# ("banco.tfstate") pra nao colidir com o state do Infra: sao dois state
# files distintos no mesmo blob container.
terraform {
  backend "azurerm" {
    resource_group_name  = "rgfiap"
    storage_account_name = "stfiap"
    container_name       = "tfstate"
    key                  = "banco.tfstate"
    use_azuread_auth     = true
  }
}
