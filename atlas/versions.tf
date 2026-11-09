terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    # Cluster M0 do Execucao (main.tf). Fixei a major 2 porque a major 1 usa
    # outra sintaxe para replication_specs (blocos em vez de atributos).
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = "~> 2.21"
    }

    # So gera a senha do usuario de banco do Atlas (main.tf) - ninguem
    # precisa conhecer essa senha, ela vai direto pro Key Vault.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
