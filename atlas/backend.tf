# Mesma storage account/container do tfstate do Infra e do resto do Banco - key
# propria ("atlas.tfstate"): o Atlas e um root separado, com state separado, pra
# o CI do Banco (que so enxerga o root principal) nunca precisar tocar no Atlas.
terraform {
  backend "azurerm" {
    resource_group_name  = "rgfiap"
    storage_account_name = "stfiap"
    container_name       = "tfstate"
    key                  = "atlas.tfstate"
    use_azuread_auth     = true
  }
}
