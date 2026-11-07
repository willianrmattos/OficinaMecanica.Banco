provider "azurerm" {
  features {}
}

# Sem argumentos de proposito: o provider le MONGODB_ATLAS_PUBLIC_KEY e
# MONGODB_ATLAS_PRIVATE_KEY (API key de organizacao) do ambiente - ou
# MONGODB_ATLAS_CLIENT_ID e MONGODB_ATLAS_CLIENT_SECRET, se eu migrar pra
# service account. Assim nenhuma credencial do Atlas passa por .tf, .tfvars
# ou state.
provider "mongodbatlas" {}
