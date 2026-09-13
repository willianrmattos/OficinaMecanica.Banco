# OficinaMecanica.Banco

Terraform do Azure SQL Database usado pelo ecossistema OficinaMecanica — o
SQL Server logico (`svsfiap`) e os 2 bancos que rodam nele
(`OficinaMecanicaDb` do monolito [OficinaMecanica](../OficinaMecanica),
`SegurancaDb` do [OficinaMecanica.Seguranca](../OficinaMecanica.Seguranca)).

Extraido do modulo `sqldb/` que vivia em
[OficinaMecanica.Infra](../OficinaMecanica.Infra) (repositorio irmao, que
centraliza todo o resto da infra do ecossistema) — ver `CLAUDE.md` para
detalhes da migracao.

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

## Recursos

| Recurso | Nome | Finalidade |
|---------|------|------------|
| `azurerm_mssql_server` | `svsfiap` | SQL Server logico (`svsfiap.database.windows.net`) |
| `azurerm_mssql_database.this` | `OficinaMecanicaDb` | Banco do monolito `OficinaMecanica` (tier sempre-gratis) |
| `azurerm_mssql_database.seguranca` | `SegurancaDb` | Banco do `OficinaMecanica.Seguranca` (serverless comum) |
| `azurerm_mssql_firewall_rule` (x2) | - | Libera servicos Azure + 1 IP de cliente opcional |

O resource group (`rgfiap`) e provisionado e gerenciado pelo
`OficinaMecanica.Infra` — este repositorio so referencia ele por nome (data
source), nao cria nem destroi.

## Rodando

```bash
cp terraform.tfvars.example terraform.tfvars
# preencher terraform.tfvars (ou usar TF_VAR_administrator_login_password)

terraform init
terraform plan
terraform apply
```

Os passos acima sao pra rodar manualmente/localmente. O CI/CD
([.github/workflows/ci.yml](.github/workflows/ci.yml)) ja automatiza isso:
`terraform plan` roda em todo PR contra `main`/`release`, e `terraform
apply` roda automaticamente em todo push (ou disparo manual) nessas
branches, autenticando via GitHub OIDC - variaveis `AZURE_CLIENT_ID`/
`AZURE_TENANT_ID`/`AZURE_SUBSCRIPTION_ID` e o secret
`TF_VAR_ADMINISTRATOR_LOGIN_PASSWORD` ja configurados no repositorio.

## Infraestrutura relacionada

Todo o resto da infra do ecossistema (AKS, ACR, Key Vault, Function App,
APIM, OIDC do GitHub Actions) vive em
[OficinaMecanica.Infra](../OficinaMecanica.Infra) — ver o `CLAUDE.md` de la
pra entender como as connection strings deste banco chegam no Key Vault sem
os dois repositorios compartilharem state.

## Stack Tecnologica

| Categoria | Tecnologia | Versao |
|-----------|-----------|--------|
| IaC | Terraform (provider `azurerm`) | >= 1.5 |
| Banco de dados | Azure SQL Database (`OficinaMecanicaDb` sempre-gratis, `SegurancaDb` serverless) | — |
| CI/CD | GitHub Actions + OIDC (Federated Identity Credential, sem client secret) | — |
