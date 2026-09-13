# OficinaMecanica.Banco - Terraform do banco de dados

## Visao Geral

Repositorio dedicado ao Terraform que provisiona o Azure SQL Database usado
pelo ecossistema OficinaMecanica — o SQL Server logico (`svsfiap`) e os 2
bancos que rodam nele (`OficinaMecanicaDb` do monolito `OficinaMecanica`,
`SegurancaDb` do `OficinaMecanica.Seguranca`).

Extraido do modulo `sqldb/` que vivia em `OficinaMecanica.Infra` (repositorio
irmao, centraliza todo o resto da infra do ecossistema). Diferente da
migracao anterior (`OficinaMecanica` -> `OficinaMecanica.Infra`, que foi so
realocacao de arquivos com o mesmo backend/state), esta foi uma divisao de
verdade: os recursos ja existiam de verdade no Azure e foram movidos de state
via `terraform state rm` (no `OficinaMecanica.Infra`) + `terraform import`
(aqui), sem destruir/recriar nada no Azure — confirmado via `terraform plan`
vazio nos dois repos apos a migracao.

## Estrutura

Terraform direto na raiz (sem pasta de modulo aninhada - o repositorio
inteiro *e* essa unica responsabilidade):

- **`main.tf`**: `data "azurerm_resource_group" "existing"` (busca por nome
  o resource group `rgfiap`, ja criado e gerenciado pelo
  `OficinaMecanica.Infra` - este repo nao cria nem destroi esse RG, so cria
  recursos dentro dele), `azurerm_mssql_server` (`svsfiap`), 2
  `azurerm_mssql_database` (`OficinaMecanicaDb` - tier sempre-gratis,
  `SegurancaDb` - serverless comum no mesmo servidor logico), 2
  `azurerm_mssql_firewall_rule` (Azure Services + IP do cliente).
- **`variables.tf`** / **`outputs.tf`**: mesmos nomes/defaults do antigo
  modulo `sqldb/`.
- **`backend.tf`**: mesma storage account/container do tfstate do
  `OficinaMecanica.Infra` (`stfiap`/`tfstate`) - **key diferente**
  (`banco.tfstate`), pra nao colidir com o state do Infra. Sao dois state
  files distintos no mesmo blob container.
- **`.github/workflows/ci.yml`**: `validate` (fmt/validate/plan em PR e
  push) + `apply` (so em push/disparo manual em `main`/`release`), via
  GitHub OIDC (identidade unica, `OficinaMecanica.Infra/github_oidc_banco`).

O campo que ativa o tier sempre-gratis (`use_free_limit`) nao existe no
provider `azurerm` e nao pode ser setado depois via `az sql db update` (so
na criacao) — por isso o `OficinaMecanicaDb` foi criado originalmente via
`az sql db create --use-free-limit true --free-limit-exhaustion-behavior AutoPause ...`
e trazido pro Terraform com `terraform import` (repetido aqui na migracao
pra esse repo, ja que import nao afeta o recurso real, so o state).

## Por que nao acopla com o state do OficinaMecanica.Infra

`OficinaMecanica.Infra` precisa da connection string do banco
(`keyvault_secrets.tf`/`seguranca_keyvault.tf`, salva no Key Vault) mas
**nao** usa `terraform_remote_state` pra ler os outputs deste repo -
acoplamento forte entre dois states remotos e evitado de proposito. Em vez
disso, o FQDN do servidor e previsivel (`<nome>.database.windows.net`), e o
`OficinaMecanica.Infra` so guarda variaveis simples (`sql_server_name`,
`sql_database_name`, `seguranca_database_name`,
`sql_administrator_login`/`_password`) que descrevem os mesmos "fatos
conhecidos" configurados aqui - mesmo padrao ja usado la pro Key Vault
(`key_vault_uri` montado a partir de `var.key_vault_name`, nao de um output
de modulo). Se o nome do servidor ou dos bancos mudar aqui, precisa
atualizar manualmente as variaveis correspondentes no `OficinaMecanica.Infra`
tambem.

## Comandos Uteis

```bash
terraform init
terraform plan
terraform apply
terraform output
```

Isso e pra rodar manualmente/localmente - o CI/CD (`.github/workflows/ci.yml`)
ja roda `plan` em todo PR e `apply` automaticamente em todo push (ou
disparo manual) em `main`/`release`, via GitHub OIDC.

## Fora de escopo (por enquanto)

- Resource group dedicado (o banco continua no `rgfiap` compartilhado, que
  o `OficinaMecanica.Infra` provisiona e gerencia).
