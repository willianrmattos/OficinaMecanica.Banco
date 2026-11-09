# MongoDB Atlas do OficinaMecanica.Execucao: projeto proprio, cluster M0
# gratuito (hospedado no Azure), um usuario de banco dedicado e a IP access
# list restrita ao IP de saida do AKS. A connection string final e gravada
# por este mesmo root no Key Vault - o OficinaMecanica.Infra so a le
# (SecretProviderClass do Execucao), nao precisa conhecer o Atlas.
#
# Este diretorio e um root Terraform separado do resto do Banco (state proprio,
# atlas.tfstate) e eu o aplico so da minha maquina: o CI do Banco nunca fala com
# o Atlas, porque a API de administracao dele exige IP fixo na API key e o
# runner do GitHub nao tem (docs/adr/0004).
#
# As credenciais da API do Atlas (MONGODB_ATLAS_PUBLIC_KEY e
# MONGODB_ATLAS_PRIVATE_KEY) vem do ambiente, nunca de arquivo - ver
# providers.tf.

resource "mongodbatlas_project" "this" {
  name   = var.atlas_project_name
  org_id = var.atlas_org_id
}

# Um cluster M0 (tier gratuito) so e criado com provider_name TENANT mais
# backing_provider_name (a nuvem real). priority 7 e a prioridade maxima,
# exigida para a unica regiao do cluster.
#
# prevent_destroy porque o M0 nao e modificavel depois de criado: qualquer
# diff que force substituicao (nome, regiao) apagaria os dados da fila de
# execucao. Prefiro que o apply falhe e eu decida conscientemente.
resource "mongodbatlas_advanced_cluster" "execucao" {
  project_id   = mongodbatlas_project.this.id
  name         = var.atlas_cluster_name
  cluster_type = "REPLICASET"

  replication_specs = [{
    region_configs = [{
      provider_name         = "TENANT"
      backing_provider_name = "AZURE"
      region_name           = var.atlas_region
      priority              = 7
      electable_specs = {
        instance_size = "M0"
      }
    }]
  }]

  lifecycle {
    prevent_destroy = true
  }
}

# Ninguem precisa saber essa senha: ela nasce aqui, vai pro Atlas e pro Key
# Vault, e para rotacionar basta "terraform apply -replace" neste recurso.
# Sem caracteres especiais porque ela entra numa URI mongodb+srv:// (evita
# depender de percent-encoding em todo cliente que montar a string).
resource "random_password" "execucao_mongo" {
  length  = 32
  special = false
}

# Menor privilegio: readWrite SOMENTE no banco do Execucao (cobre as
# operacoes que a aplicacao faz no start, createCollection e createIndex,
# alem de CRUD e transacoes) e escopado a este cluster. Nao e atlasAdmin e
# nao alcanca nenhum outro banco, mesmo que o projeto ganhe outros clusters.
resource "mongodbatlas_database_user" "execucao_app" {
  project_id         = mongodbatlas_project.this.id
  username           = var.execucao_mongo_username
  password           = random_password.execucao_mongo.result
  auth_database_name = "admin"

  roles {
    role_name     = "readWrite"
    database_name = var.execucao_mongo_database_name
  }

  scopes {
    name = mongodbatlas_advanced_cluster.execucao.name
    type = "CLUSTER"
  }
}

# Unica origem liberada: o IP de saida do AKS, como /32. De proposito nao ha
# 0.0.0.0/0 nem nenhum outro CIDR aqui - o M0 nao suporta private endpoint
# nem VNet peering, entao a allowlist por IP e o unico controle de rede.
resource "mongodbatlas_project_ip_access_list" "aks_egress" {
  project_id = mongodbatlas_project.this.id
  cidr_block = "${var.aks_egress_ip}/32"
  comment    = "Saida do AKS aksfiap (Execucao). Atualizar se o cluster for recriado."
}

data "azurerm_key_vault" "this" {
  name                = var.key_vault_name
  resource_group_name = var.resource_group_name
}

locals {
  # standard_srv vem como "mongodb+srv://<host>"; reaproveito so o host pra
  # montar a string com credenciais. authSource=admin porque o usuario do
  # Atlas e criado no banco admin, mesmo tendo role so em "execucao".
  execucao_mongo_srv_host = trimprefix(mongodbatlas_advanced_cluster.execucao.connection_strings.standard_srv, "mongodb+srv://")

  # Sensivel por derivacao: depende de random_password.result.
  execucao_mongo_connection_string = "mongodb+srv://${urlencode(mongodbatlas_database_user.execucao_app.username)}:${urlencode(random_password.execucao_mongo.result)}@${local.execucao_mongo_srv_host}/${var.execucao_mongo_database_name}?authSource=admin&retryWrites=true&w=majority"
}

# Quem grava o secret e este root, aplicado so da minha maquina por um
# administrador do Key Vault (Key Vault Administrator): o CI do Banco nao aplica
# nem le este root, e a identidade github_oidc_banco nao tem role nenhuma nesse
# secret (docs/adr/0004). O depends_on garante que a connection string so e
# publicada depois de o usuario existir e de o IP do AKS estar liberado.
resource "azurerm_key_vault_secret" "execucao_mongo_connection_string" {
  name         = var.execucao_mongo_secret_name
  value        = local.execucao_mongo_connection_string
  key_vault_id = data.azurerm_key_vault.this.id
  content_type = "mongodb-connection-string"

  tags = var.tags

  depends_on = [
    mongodbatlas_database_user.execucao_app,
    mongodbatlas_project_ip_access_list.aks_egress,
  ]
}
