# OficinaMecanica.Banco

Terraform dos dados do ecossistema OficinaMecanica:

- **Azure SQL Database**: o SQL Server logico (`svsfiap`) e os 3 bancos que
  rodam nele (`OficinaMecanicaDb` do monolito
  [OficinaMecanica](../OficinaMecanica), `SegurancaDb` do
  [OficinaMecanica.Seguranca](../OficinaMecanica.Seguranca) e `BillingDb` do
  `OficinaMecanica.Billing`), cada um com um usuario SQL contido dedicado.
- **MongoDB Atlas (cluster M0 gratuito)** do `OficinaMecanica.Execucao`, com
  a connection string gravada no Key Vault por este repositorio.

Extraido do modulo `sqldb/` que vivia em
[OficinaMecanica.Infra](../OficinaMecanica.Infra) (repositorio irmao, que
centraliza todo o resto da infra do ecossistema) — ver `CLAUDE.md` para
detalhes da migracao.

> Estado: BillingDb, usuarios SQL e Atlas estao escritos e validados so com
> `terraform fmt`/`validate`; nada foi aplicado (ver `CLAUDE.md`).

Este repositorio e so Terraform — nao expoe nenhuma API HTTP propria (sem
Swagger/Postman aplicavel). As APIs que consomem esses bancos sao as dos
repositorios [OficinaMecanica](../OficinaMecanica) e
[OficinaMecanica.Seguranca](../OficinaMecanica.Seguranca).

## Diagramas

| Documento | Arquivo |
|-----------|---------|
| Modelo de Dados (ER - OficinaMecanicaDb e SegurancaDb) | [docs/diagramas/modelo-de-dados.jpg](docs/diagramas/modelo-de-dados.jpg) |

## RFCs (decisoes de "por que essa direcao")

| RFC | Titulo |
|-----|--------|
| 0001 | [Escolha do banco de dados (Azure SQL Database serverless)](docs/rfc/0001-escolha-do-banco-de-dados.md) |

## ADRs (decisoes tecnicas pontuais)

| ADR | Titulo |
|-----|--------|
| 0001 | [Extracao do banco em repositorio e state proprios](docs/adr/0001-extracao-em-repositorio-e-state-proprios.md) |
| 0002 | [MongoDB Atlas M0 provisionado por Terraform neste repositorio](docs/adr/0002-mongodb-atlas-m0-provisionado-por-terraform.md) |
| 0003 | [BillingDb e usuarios SQL dedicados por banco](docs/adr/0003-billingdb-e-usuarios-sql-dedicados-por-banco.md) |

## Recursos

| Recurso | Nome | Finalidade |
|---------|------|------------|
| `azurerm_mssql_server` | `svsfiap` | SQL Server logico (`svsfiap.database.windows.net`) |
| `azurerm_mssql_database.this` | `OficinaMecanicaDb` | Banco do monolito `OficinaMecanica` (tier sempre-gratis) |
| `azurerm_mssql_database.seguranca` | `SegurancaDb` | Banco do `OficinaMecanica.Seguranca` (serverless comum) |
| `azurerm_mssql_database.billing` | `BillingDb` | Banco do `OficinaMecanica.Billing` (serverless comum) |
| `azurerm_mssql_firewall_rule` (x2) | - | Libera servicos Azure + 1 IP de cliente opcional |
| `mongodbatlas_project` | `OficinaMecanica` | Projeto proprio no Atlas |
| `mongodbatlas_advanced_cluster.execucao` | `execucao` | Cluster M0 gratuito (Azure) do `OficinaMecanica.Execucao` |
| `mongodbatlas_database_user.execucao_app` | `execucao_app` | `readWrite` somente no banco `execucao` |
| `mongodbatlas_project_ip_access_list.aks_egress` | - | `/32` do IP de saida do AKS (sem `0.0.0.0/0`) |
| `azurerm_key_vault_secret.execucao_mongo_connection_string` | `execucao-mongo-connection-string` | Connection string do Mongo, no `kvfiap` |

Usuarios SQL contidos (criados por `sql/criar-usuarios.sql` no CI, nao por
Terraform): `app_os` em `OficinaMecanicaDb`, `app_seguranca` em `SegurancaDb`,
`app_billing` em `BillingDb`, cada um `db_owner` so no proprio banco.

O resource group (`rgfiap`) e o Key Vault (`kvfiap`) sao provisionados e
gerenciados pelo `OficinaMecanica.Infra` — este repositorio so referencia
eles por nome (data source), nao cria nem destroi.

## Rodando

```bash
cp terraform.tfvars.example terraform.tfvars
# preencher so o que nao e segredo; o resto entra por variavel de ambiente:
#   TF_VAR_administrator_login_password, TF_VAR_sql_app_os_password,
#   TF_VAR_sql_app_seguranca_password, TF_VAR_sql_app_billing_password,
#   TF_VAR_atlas_org_id, TF_VAR_aks_egress_ip,
#   MONGODB_ATLAS_PUBLIC_KEY, MONGODB_ATLAS_PRIVATE_KEY

terraform init
terraform plan
terraform apply

# depois do apply, por banco, com o go-sqlcmd conectado como administrador;
# as senhas vao por variavel de ambiente (SQLCMDPASSWORD e SenhaUsuario), nunca
# na linha de comando:
# sqlcmd -S <server_fqdn> -d <banco> -U <admin> -b -i sql/criar-usuarios.sql \
#   -v NomeUsuario=<app_...>
```

Pre-requisitos que dependem de acao externa: conta e organizacao no MongoDB
Atlas com uma API key de organizacao, o IP publico de saida do AKS
(`aks_egress_ip`) e, para o CI, a role `Key Vault Secrets Officer` do
`github_oidc_banco` escopada ao secret `execucao-mongo-connection-string`
(concedida pelo Infra). Como obter cada um esta no `CLAUDE.md` e no ADR 0002.

O CI/CD ([.github/workflows/ci.yml](.github/workflows/ci.yml)) automatiza o
mesmo fluxo depois do bootstrap:
`terraform plan` roda em todo PR contra `main`/`release`, e `terraform
apply` roda automaticamente em todo push (ou disparo manual) nessas
branches, seguido da criacao dos usuarios SQL (so se o apply terminar com
sucesso), autenticando via GitHub OIDC -
variaveis `AZURE_CLIENT_ID`/`AZURE_TENANT_ID`/`AZURE_SUBSCRIPTION_ID` e os
secrets `TF_VAR_ADMINISTRATOR_LOGIN_PASSWORD`,
`TF_VAR_SQL_APP_OS_PASSWORD`, `TF_VAR_SQL_APP_SEGURANCA_PASSWORD`,
`TF_VAR_SQL_APP_BILLING_PASSWORD`, `TF_VAR_AKS_EGRESS_IP`,
`TF_VAR_ATLAS_ORG_ID`, `MONGODB_ATLAS_PUBLIC_KEY` e
`MONGODB_ATLAS_PRIVATE_KEY` precisam estar configurados no repositorio.

Ordem entre repositorios: Banco primeiro (bancos, usuarios, Atlas), Infra
depois (connection strings no Key Vault), deploy dos servicos por ultimo.

Bootstrap (primeira vez), resumido; o passo a passo esta no `CLAUDE.md`:

1. Aplicar o Banco localmente com um administrador humano (`Key Vault
   Administrator`): cria `BillingDb`, o Atlas e o secret do Mongo. O CI nao
   consegue, porque a role do CI no Key Vault so alcanca esse secret depois de
   ele existir.
2. Criar os usuarios SQL: rodando `sql/criar-usuarios.sql` localmente logo em
   seguida (recomendado, antes de o Infra trocar as connection strings dos
   servicos que ja rodam) ou deixando o primeiro apply bem-sucedido do CI faze-lo.
3. Infra (CI): cria a role escopada ao secret e as connection strings.
4. Dai em diante o CI do Banco funciona.

Decisao pendente antes do merge em `release`: como o CI alcanca a API do Atlas
(access list da API key); ver ADR 0002.

## Infraestrutura relacionada

Todo o resto da infra do ecossistema (AKS, ACR, Key Vault, Function App,
APIM, OIDC do GitHub Actions) vive em
[OficinaMecanica.Infra](../OficinaMecanica.Infra) — ver o `CLAUDE.md` de la
pra entender como as connection strings deste banco chegam no Key Vault sem
os dois repositorios compartilharem state.

## Stack Tecnologica

| Categoria | Tecnologia | Versao |
|-----------|-----------|--------|
| IaC | Terraform (providers `azurerm`, `mongodbatlas`, `random`) | >= 1.5 (CI usa 1.15.7) |
| Banco relacional | Azure SQL Database (`OficinaMecanicaDb` sempre-gratis, `SegurancaDb` e `BillingDb` serverless) | — |
| Banco de documentos | MongoDB Atlas M0 (hospedado no Azure) | — |
| CI/CD | GitHub Actions + OIDC (Federated Identity Credential, sem client secret) | — |
