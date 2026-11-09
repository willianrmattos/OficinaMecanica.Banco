# OficinaMecanica.Banco - Terraform dos bancos de dados

## Visao Geral

Repositorio dedicado ao Terraform dos dados do ecossistema OficinaMecanica:

- **Azure SQL Database**: o SQL Server logico (`svsfiap`) e os 3 bancos que
  rodam nele (`OficinaMecanicaDb` do OS Service (o antigo monolito) `OficinaMecanica`, `SegurancaDb`
  do `OficinaMecanica.Seguranca`, `BillingDb` do `OficinaMecanica.Billing`),
  com um usuario SQL contido dedicado por banco.
- **MongoDB Atlas (cluster M0 gratuito)** do `OficinaMecanica.Execucao`:
  projeto, cluster, usuario de banco e IP access list, com a connection string
  gravada por este repo no Key Vault (`kvfiap`). Vive num **root Terraform
  separado** (`atlas/`, state proprio `atlas.tfstate`) e e aplicado **so
  localmente**, da minha maquina: o CI do Banco nao o aplica nem o le (ADR 0004).

Extraido do modulo `sqldb/` que vivia em `OficinaMecanica.Infra` (repositorio
irmao, centraliza todo o resto da infra do ecossistema). Diferente da
migracao anterior (`OficinaMecanica` -> `OficinaMecanica.Infra`, que foi so
realocacao de arquivos com o mesmo backend/state), esta foi uma divisao de
verdade: os recursos ja existiam de verdade no Azure e foram movidos de state
via `terraform state rm` (no `OficinaMecanica.Infra`) + `terraform import`
(aqui), sem destruir/recriar nada no Azure — confirmado via `terraform plan`
vazio nos dois repos apos a migracao.

## Estado atual: NADA disto foi aplicado

BillingDb, usuarios SQL e Atlas (a parte do Terraform dos microsservicos) estao so
escritos e validados com `terraform fmt -check`, `terraform init
-backend=false` e `terraform validate`. Nenhum `plan`/`apply`, nenhum SQL
executado, nenhuma conta Atlas usada. O script `sql/criar-usuarios.sql` teve
a sintaxe checada por parser offline, nao por execucao. Os ADRs 0002 e 0003
listam o que ainda precisa ser validado no ambiente real.

## Estrutura

Dois roots Terraform independentes: o principal, direto na raiz (sem pasta de
modulo aninhada), e `atlas/` (MongoDB Atlas, state proprio, so local).

Root principal (SQL):

- **`main.tf`**: `data "azurerm_resource_group" "existing"` (busca por nome
  o resource group `rgfiap`, ja criado e gerenciado pelo
  `OficinaMecanica.Infra` - este repo nao cria nem destroi esse RG, so cria
  recursos dentro dele), `azurerm_mssql_server` (`svsfiap`), 3
  `azurerm_mssql_database` (`OficinaMecanicaDb` - tier sempre-gratis,
  `SegurancaDb` e `BillingDb` - serverless comum no mesmo servidor logico), 2
  `azurerm_mssql_firewall_rule` (Azure Services + IP do cliente).
- **`sql/criar-usuarios.sql`**: cria (ou sincroniza a senha de) o usuario
  contido do banco em que o `sqlcmd` esta conectado e o poe em `db_owner`.
  Idempotente, sem senha literal (variaveis `NomeUsuario`/`SenhaUsuario` por
  `-v`). Roda 1x por banco: `app_os` (OficinaMecanicaDb), `app_seguranca`
  (SegurancaDb), `app_billing` (BillingDb). O azurerm nao cria usuario
  contido, por isso e script e nao Terraform.
- **`variables.tf`** / **`outputs.tf`**: as variaveis/outputs originais do
  modulo `sqldb/` mais as de BillingDb e usuarios SQL (secao abaixo). Nenhum
  output expoe segredo.
- **`versions.tf`** / **`providers.tf`**: so `azurerm ~> 4.0`.
- **`backend.tf`**: mesma storage account/container do tfstate do
  `OficinaMecanica.Infra` (`stfiap`/`tfstate`) - **key diferente**
  (`banco.tfstate`), pra nao colidir com o state do Infra. Sao dois state
  files distintos no mesmo blob container (tres, contando o `atlas.tfstate`).
- **`.github/workflows/ci.yml`**: `validate` (fmt/validate/plan do root
  principal em PR e push) + `apply` (so em push/disparo manual em
  `main`/`release`, so do root principal), via GitHub OIDC (identidade unica,
  `OficinaMecanica.Infra/github_oidc_banco`). O `validate` roda `terraform fmt
  -check -recursive` (cobre o `atlas/`) e o passo "Terraform Validate (atlas)"
  (`init -backend=false` + `validate`, sem credenciais); o `plan` e o `apply`
  nao tocam no `atlas/`.
  O `apply` roda, depois do `terraform apply`: leitura dos outputs (falha se
  algum vier vazio), instalacao do go-sqlcmd v1.10.0 pinado com sha256 (o
  `ubuntu-latest` nao traz sqlcmd), regra temporaria de firewall com o IP do
  runner, o script SQL nos 3 bancos (senha por variavel de ambiente, nao por
  argumento; ate 10 tentativas: firewall propagando, banco serverless
  pausado) e remocao da regra (`if: always()`). O `validate` nao executa SQL.
  Se o `Terraform Apply` falhar, os passos seguintes sao PULADOS (nao tem
  `if:`, exceto a remocao da regra de firewall, que so roda se a regra chegou
  a ser criada): os usuarios SQL so nascem numa execucao em que o apply termina. Em
  PR a execucao anterior e cancelada; em push/disparo em `main`/`release`
  nao (cancelar o apply no meio pode deixar um recurso criado fora do state).
  Timeouts: 20 min no `validate`, 60 min no `apply`.
- **`docs/adr/`**: ADR 0001 (extracao do banco), 0002 (Atlas M0 por
  Terraform), 0003 (BillingDb e usuarios SQL dedicados) e 0004 (Atlas aplicado
  so localmente, fora do CI).

Root `atlas/` (MongoDB Atlas, state `atlas.tfstate`, aplicado so localmente;
`atlas/README.md` tem o passo a passo):

- **`atlas/main.tf`**: `mongodbatlas_project`, `mongodbatlas_advanced_cluster`
  (M0, `TENANT`/`AZURE`, `prevent_destroy`), `random_password` +
  `mongodbatlas_database_user` (`execucao_app`, `readWrite` so no banco
  `execucao`, escopado ao cluster), `mongodbatlas_project_ip_access_list`
  (`/32` do egress do AKS, nunca `0.0.0.0/0`), `data "azurerm_key_vault"`
  (`kvfiap`) e `azurerm_key_vault_secret` `execucao-mongo-connection-string`.
- **`atlas/variables.tf`** / **`outputs.tf`**: as variaveis `atlas_*`,
  `execucao_mongo_*`, `key_vault_name` e `aks_egress_ip` existem so aqui (secao
  abaixo). Nenhum output expoe segredo (a connection string do Mongo so existe
  no Key Vault e no `atlas.tfstate`).
- **`atlas/versions.tf`** / **`providers.tf`**: `azurerm ~> 4.0`,
  `mongodbatlas ~> 2.21` e `random ~> 3.6`. O provider do Atlas fica sem
  argumentos: le as credenciais do ambiente.
- **`atlas/backend.tf`**: mesma storage account/container (`stfiap`/`tfstate`),
  key `atlas.tfstate`.

O campo que ativa o tier sempre-gratis (`use_free_limit`) nao existe no
provider `azurerm` e nao pode ser setado depois via `az sql db update` (so
na criacao) — por isso o `OficinaMecanicaDb` foi criado originalmente via
`az sql db create --use-free-limit true --free-limit-exhaustion-behavior AutoPause ...`
e trazido pro Terraform com `terraform import` (repetido aqui na migracao
pra esse repo, ja que import nao afeta o recurso real, so o state).

## Variaveis novas (sem default = obrigatorias)

| Variavel | Sensivel | Observacao |
|----------|----------|------------|
| `billing_database_name`, `billing_sku_name`, `billing_max_size_gb`, `billing_min_capacity`, `billing_auto_pause_delay_in_minutes` | nao | defaults: `BillingDb`, `GP_S_Gen5_2`, 5, 0.5, 60 |
| `sql_app_os_password`, `sql_app_seguranca_password`, `sql_app_billing_password` | **sim** | sem default; MESMOS nomes no Infra; `validation` de 16-128 caracteres seguros com maiuscula/minuscula/digito; nenhum recurso as consome (so o script SQL do CI) |

Variaveis do root `atlas/` (declaradas so em `atlas/variables.tf`; o root
principal nao as conhece):

| Variavel | Sensivel | Observacao |
|----------|----------|------------|
| `key_vault_name` | nao | default `kvfiap` |
| `atlas_org_id` | nao | sem default; 24 hex da organizacao no Atlas |
| `atlas_project_name`, `atlas_cluster_name`, `atlas_region` | nao | defaults `OficinaMecanica`, `execucao`, `EUROPE_NORTH` (Irlanda) |
| `execucao_mongo_database_name`, `execucao_mongo_username`, `execucao_mongo_secret_name` | nao | defaults `execucao`, `execucao_app`, `execucao-mongo-connection-string` |
| `aks_egress_ip` | nao | sem default; um unico IPv4 publico: CIDR, `0.0.0.0` e faixas privadas/loopback/link-local/CGNAT/multicast/reservadas sao recusados |
| `MONGODB_ATLAS_PUBLIC_KEY`, `MONGODB_ATLAS_PRIVATE_KEY` | **sim** | nao sao variaveis Terraform: o provider `mongodbatlas` as le do ambiente |

**Protecao de branch**: o ruleset `protect-main-release` (so `main` e `release`: sem apagar nem force-push, PR
obrigatorio e o check `Terraform Validate` exigido; sem bypass) ja esta ATIVO no GitHub e o arquivo versionado
`.github/rulesets/protect-main-release.json` e equivalente a ele. Nao ha script para aplicar: se precisar recriar ou
alterar, use a GitHub CLI com esse arquivo (`gh api --method PUT repos/willianrmattos/OficinaMecanica.Banco/rulesets/<id> --input
.github/rulesets/protect-main-release.json`; o `<id>` sai de `gh api repos/willianrmattos/OficinaMecanica.Banco/rulesets`).

## Segredos e variaveis do GitHub Actions deste repo

Secrets (todos novos, exceto o primeiro; mapeados em `ci.yml` para `TF_VAR_*`
em minusculo, como o Terraform exige em Linux):

- `TF_VAR_ADMINISTRATOR_LOGIN_PASSWORD` (ja existia; no passo de SQL vira
  `SQLCMDPASSWORD`)
- `TF_VAR_SQL_APP_OS_PASSWORD`, `TF_VAR_SQL_APP_SEGURANCA_PASSWORD`,
  `TF_VAR_SQL_APP_BILLING_PASSWORD`

Nenhuma credencial nem variavel do Atlas fica no GitHub: o CI nao aplica nem le
o `atlas/` (ADR 0004). Se os secrets `TF_VAR_AKS_EGRESS_IP`, `TF_VAR_ATLAS_ORG_ID`,
`MONGODB_ATLAS_PUBLIC_KEY` e `MONGODB_ATLAS_PRIVATE_KEY` existirem nas
configuracoes do repositorio, podem ser apagados.

Variables (ja existiam): `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
`AZURE_SUBSCRIPTION_ID`.

Rodando localmente, as mesmas coisas entram por variavel de ambiente
(`TF_VAR_*` no root principal; `TF_VAR_atlas_org_id`, `TF_VAR_aks_egress_ip` e
`MONGODB_ATLAS_*` no `atlas/`), nunca em `terraform.tfvars` com valor sensivel;
os `terraform.tfvars.example` (um por root) so tem placeholders e a lista do que
fica fora do arquivo.

## Contrato com o OficinaMecanica.Infra

- Nomes: bancos `OficinaMecanicaDb`/`SegurancaDb`/`BillingDb` no `svsfiap`;
  usuarios `app_os`/`app_seguranca`/`app_billing`; variaveis de senha
  `sql_app_os_password`/`sql_app_seguranca_password`/`sql_app_billing_password`
  (o Infra as usa para montar as connection strings no Key Vault, com
  `Initial Catalog` - usuario contido nao conecta no master); secret
  `execucao-mongo-connection-string` no `kvfiap` (gravado AQUI, pelo root
  `atlas/`, lido pelo Execucao via SecretProviderClass).
- O Infra da ao `github_oidc_banco` o `Reader` no RG e o `Contributor` no SQL
  Server (o `Contributor` tambem cobre a regra temporaria de firewall do CI). A
  identidade **nao tem role no secret do Mongo**: o CI nao grava esse secret
  (a identidade tem credencial `pull_request`, ver ADR 0004 e ADR 0005 do
  Infra).
- Continua sem `terraform_remote_state`: o `aks_egress_ip` e copiado a mao do
  Infra/cluster para o `atlas/`.

## Ordem de aplicacao e bootstrap

Ordem em regime: **Banco -> Infra -> deploy dos servicos.** O Infra monta as
connection strings com os usuarios `app_*`; se ele aplicar antes de esses
usuarios existirem, OS Service e Seguranca (que hoje usam o admin) perdem a
conexao.

Bootstrap (primeira vez), nesta ordem:

1. **Root principal do Banco, localmente, com um administrador humano** (`az
   login` com `Storage Blob Data Contributor` no tfstate; segredos por
   `TF_VAR_*`; `client_ip_address` com o meu IP se eu for rodar o SQL daqui).
   Cria `BillingDb`.
2. **Usuarios SQL** (`sql/criar-usuarios.sql`), por UMA destas vias:
   - *Local, logo depois do passo 1 (recomendada)*: garante que `app_os`,
     `app_seguranca` e `app_billing` existem antes de o Infra trocar as
     connection strings dos servicos que ja rodam. Em PowerShell, por banco:
     ```powershell
     $env:SQLCMDPASSWORD = '<senha do admin>'
     $env:SenhaUsuario   = '<senha do usuario do banco>'
     sqlcmd -S svsfiap.database.windows.net -d OficinaMecanicaDb -U adminfiap -b -i sql/criar-usuarios.sql -v NomeUsuario=app_os
     # idem: -d SegurancaDb -v NomeUsuario=app_seguranca ; -d BillingDb -v NomeUsuario=app_billing
     ```
     Usar o go-sqlcmd (mesma variante do CI) e apagar as variaveis de ambiente
     depois.
   - *Pelo CI*: o primeiro apply do CI que terminar com sucesso cria os tres.
     So serve se nenhum servico ja em uso depender dos usuarios antes disso. Se
     o `Terraform Apply` falhar, os passos de SQL sao pulados e os usuarios so
     nascem numa execucao posterior que passe.
3. **`atlas/`, localmente, com um administrador humano** (`az login` com `Key
   Vault Administrator` no `kvfiap` e `Storage Blob Data Contributor` no
   tfstate; `MONGODB_ATLAS_PUBLIC_KEY`, `MONGODB_ATLAS_PRIVATE_KEY`,
   `TF_VAR_atlas_org_id` e `TF_VAR_aks_egress_ip` no ambiente; a access list da
   API key do Atlas precisa aceitar o IP da maquina). Cria o projeto, o cluster
   M0, o usuario, a IP list e o secret `execucao-mongo-connection-string`:
   ```bash
   cd atlas
   terraform init
   terraform plan
   terraform apply
   ```
4. **Infra (CI)**: cria as connection strings com os usuarios `app_*` e o resto.

O `atlas/` precisa estar aplicado antes do **deploy do Execucao** (o pod le o
secret `execucao-mongo-connection-string` pelo SecretProviderClass); nao e
pre-requisito do apply do Infra. A ordem Banco -> Infra vem dos usuarios SQL.
O `atlas/` so precisa que o `kvfiap` (do Infra) ja exista, porque o referencia
por nome (data source).

Se o secret `execucao-mongo-connection-string` for apagado do Key Vault,
aplicar o `atlas/` de novo (localmente) o recria.

## O que exige conta e acao minha (nao automatizavel)

- **Conta e organizacao no MongoDB Atlas** + API key de organizacao (role
  minima esperada: `Organization Project Creator`; confirmar no primeiro
  apply) com o IP da minha maquina na access list da key, e o `atlas_org_id`.
  So para aplicar o `atlas/` localmente: o CI nao usa nada disso (o Atlas recusa
  `0.0.0.0/0` na access list de API key e o runner do GitHub tem IP variavel;
  ver ADR 0004).
- **`aks_egress_ip`** (entrada do `atlas/`): IP publico de saida do AKS:
  `az aks show -g rgfiap -n aksfiap --query "networkProfile.loadBalancerProfile.effectiveOutboundIPs[].id" -o tsv`
  e depois `az network public-ip show --ids <id> --query ipAddress -o tsv`.
  Se o cluster for recriado ou o load balancer de saida mudar, o IP muda: os
  pods do Execucao perdem acesso ao Mongo ate atualizar `TF_VAR_aks_egress_ip` e
  aplicar o `atlas/` de novo.
- Criar os secrets do GitHub listados acima (so os do SQL e as variables do
  Azure).
- Fazer o bootstrap local descrito em "Ordem de aplicacao e bootstrap".

## Atlas M0: limites e riscos

512 MB (inclui indices), 500 conexoes, ~100 operacoes/s (estrangula, nao
rejeita), 10 GB de entrada/saida por 7 dias, 1 cluster gratuito por projeto,
pausa apos 30 dias sem conexoes. O cluster M0 nao e modificavel depois de
criado: trocar nome ou regiao recria o cluster e apaga os dados (por isso
`prevent_destroy`). Rotacionar a senha do usuario do Atlas:
`terraform -chdir=atlas apply -replace=random_password.execucao_mongo` (da maquina
de um administrador) e reiniciar os pods.
Verificado no Atlas real em 2026-11-09: o M0 em `EUROPE_NORTH` e a criacao do cluster pelo
provider 2.x (apply do `atlas/`). Nao verificado: transacoes multi-documento no M0 (necessarias ao
outbox `MassTransit.MongoDb`; fallback do spike do outbox, ver o ADR 0002: outbox embutido +
relay).

## Por que nao acopla com o state do OficinaMecanica.Infra

`OficinaMecanica.Infra` precisa da connection string do banco
(`keyvault_secrets.tf`/`seguranca_keyvault.tf`, salva no Key Vault) mas
**nao** usa `terraform_remote_state` pra ler os outputs deste repo -
acoplamento forte entre dois states remotos e evitado de proposito. Em vez
disso, o FQDN do servidor e previsivel (`<nome>.database.windows.net`), e o
`OficinaMecanica.Infra` so guarda variaveis simples (`sql_server_name`,
`sql_database_name`, `seguranca_database_name`,
`sql_app_os_*`, `sql_app_seguranca_*` e `sql_app_billing_*`, o login e a senha do usuario SQL dedicado de cada banco) que descrevem os mesmos "fatos
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

Esses comandos, na raiz, sao do root principal (SQL). O Atlas e outro root:
`cd atlas` (ou `terraform -chdir=atlas <comando>`) e as variaveis de ambiente da
secao "Ordem de aplicacao e bootstrap" (passo 3).

Isso e pra rodar manualmente/localmente - o CI/CD (`.github/workflows/ci.yml`)
ja roda `plan` em todo PR e `apply` automaticamente em todo push (ou
disparo manual) em `main`/`release`, via GitHub OIDC, so no root principal; do
`atlas/` o CI so valida o codigo.

Validacao sem tocar em nada (o que foi feito ate agora): `terraform fmt
-check -recursive` (cobre os dois roots), `terraform init -backend=false` e
`terraform validate` em cada root (`terraform -chdir=atlas init -backend=false`
e `terraform -chdir=atlas validate` para o Atlas).
Se ja existir um `.terraform/` inicializado com o backend remoto, usar
`TF_DATA_DIR=<pasta temporaria>` no `init -backend=false`, senao o Terraform
tenta autenticar no backend.

## Fora de escopo (por enquanto)

- Resource group dedicado (o banco continua no `rgfiap` compartilhado, que
  o `OficinaMecanica.Infra` provisiona e gerencia).
- Dois usuarios SQL por banco (migration `db_owner` + runtime
  `db_datareader`/`db_datawriter`) e autenticacao Entra ID sem senha: ver ADR
  0003.
- Private endpoint/VNet peering para o Atlas (o M0 nao suporta).
