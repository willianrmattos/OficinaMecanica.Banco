# OficinaMecanica.Banco

Terraform do Azure SQL Database usado pelo ecossistema OficinaMecanica — o
SQL Server logico (`svsfiap`) e os 2 bancos que rodam nele
(`OficinaMecanicaDb` do monolito [OficinaMecanica](../OficinaMecanica),
`SegurancaDb` do [OficinaMecanica.Seguranca](../OficinaMecanica.Seguranca)).

Extraido do modulo `sqldb/` que vivia em
[OficinaMecanica.Infra](../OficinaMecanica.Infra) (repositorio irmao, que
centraliza todo o resto da infra do ecossistema) — ver `CLAUDE.md` para
detalhes da migracao.

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

## Infraestrutura relacionada

Todo o resto da infra do ecossistema (AKS, ACR, Key Vault, Function App,
APIM, OIDC do GitHub Actions) vive em
[OficinaMecanica.Infra](../OficinaMecanica.Infra) — ver o `CLAUDE.md` de la
pra entender como as connection strings deste banco chegam no Key Vault sem
os dois repositorios compartilharem state.
