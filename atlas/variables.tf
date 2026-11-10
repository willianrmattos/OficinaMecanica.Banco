variable "resource_group_name" {
  description = "Nome do resource group ja existente (rgfiap, criado pelo OficinaMecanica.Infra) onde o Key Vault esta - so uma referencia por nome (data source), este root nao cria nem gerencia o resource group."
  type        = string
  default     = "rgfiap"
}

variable "key_vault_name" {
  description = "Nome do Key Vault ja existente (kvfiap, criado pelo OficinaMecanica.Infra) onde este repositorio grava a connection string do MongoDB Atlas do Execucao - so uma referencia por nome (data source). Quem aplica este root e um administrador do Key Vault (Key Vault Administrator), da propria maquina: o CI do Banco nao aplica nem le este root (docs/adr/0004)."
  type        = string
  default     = "kvfiap"
}

variable "atlas_org_id" {
  description = "ID da organizacao do MongoDB Atlas (24 caracteres hexadecimais, em Organization Settings) onde o projeto e criado. Sem valor padrao: definir via TF_VAR_atlas_org_id. As credenciais da API do Atlas NAO sao variaveis: o provider le MONGODB_ATLAS_PUBLIC_KEY e MONGODB_ATLAS_PRIVATE_KEY do ambiente."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{24}$", var.atlas_org_id))
    error_message = "atlas_org_id deve ter 24 caracteres hexadecimais minusculos (ID da organizacao no Atlas)."
  }
}

variable "atlas_project_name" {
  description = "Nome do projeto do Atlas criado por este repositorio. Projeto proprio (nao compartilhado) porque o limite do M0 e de 1 cluster gratuito por projeto e porque usuarios, IP access list e API keys do Atlas sao escopados por projeto."
  type        = string
  default     = "OficinaMecanica"
}

variable "atlas_cluster_name" {
  description = "Nome do cluster M0 gratuito do Execucao no Atlas (letras, digitos e hifens). Um cluster M0 nao pode ser modificado depois de criado, entao trocar o nome recria o cluster e perde os dados."
  type        = string
  default     = "execucao"
}

variable "atlas_region" {
  description = "Regiao do cluster M0 no Atlas, no formato do Atlas para provedor AZURE (ex: EUROPE_NORTH = Irlanda, EUROPE_WEST = Paises Baixos, US_EAST_2 = Virginia, CANADA_CENTRAL = Toronto). Nem toda regiao do Azure oferece o tier gratuito: confirmar na coluna 'Free' da tabela de regioes Azure da documentacao do Atlas antes do apply. Trocar a regiao recria o cluster (M0 nao e modificavel) e perde os dados."
  type        = string
  default     = "EUROPE_NORTH"
}

variable "execucao_mongo_database_name" {
  description = "Nome do banco MongoDB do Execucao. O usuario de banco do Atlas recebe readWrite somente nele, e a aplicacao le o mesmo nome em MongoDb:Database (o padrao do codigo tambem e 'execucao')."
  type        = string
  default     = "execucao"
}

variable "execucao_mongo_username" {
  description = "Usuario de banco do Atlas dedicado ao Execucao (role readWrite somente no banco execucao, nunca atlasAdmin). A senha e gerada pelo Terraform (random_password) e so existe no state e no Key Vault."
  type        = string
  default     = "execucao_app"
}

variable "execucao_mongo_secret_name" {
  description = "Nome do secret no Key Vault que recebe a connection string do MongoDB do Execucao. O OficinaMecanica.Infra referencia esse nome exato (SecretProviderClass do Execucao), entao so mudar aqui junto com o Infra."
  type        = string
  default     = "execucao-mongo-connection-string"
}

variable "aks_egress_ip" {
  description = "IP publico de SAIDA do cluster AKS (aksfiap), unica origem liberada na IP access list do Atlas (/32, nunca 0.0.0.0/0). Sem valor padrao: definir via TF_VAR_aks_egress_ip. Se o cluster for recriado ou o load balancer de saida mudar, o IP muda e os pods perdem acesso ao Mongo (timeout de selecao de servidor) ate este valor ser atualizado e o apply rodar de novo."
  type        = string

  # A primeira regex exige quatro octetos sem zero a esquerda (a segunda compara o
  # texto, e "010.0.0.1" escaparia dela). A segunda recusa o que nunca e origem
  # publica de saida: 0/8, 10/8, 100.64/10 (CGNAT), 127/8, 169.254/16, 172.16/12,
  # 192.168/16 e 224.0.0.0 em diante (multicast e reservado).
  validation {
    condition = (
      can(cidrnetmask("${var.aks_egress_ip}/32")) &&
      can(regex("^(0|[1-9][0-9]{0,2})(\\.(0|[1-9][0-9]{0,2})){3}$", var.aks_egress_ip)) &&
      !can(regex("^(0|10|127|22[4-9]|2[3-5][0-9])\\.|^100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.|^169\\.254\\.|^172\\.(1[6-9]|2[0-9]|3[01])\\.|^192\\.168\\.", var.aks_egress_ip))
    )
    error_message = "aks_egress_ip deve ser um unico IPv4 valido de origem publica (ex: 203.0.113.10): sem CIDR, sem 0.0.0.0 e sem faixas privadas, loopback, link-local, CGNAT, multicast ou reservadas."
  }
}

variable "tags" {
  description = "Tags aplicadas aos recursos."
  type        = map(string)
  default     = {}
}
