# OficinaMecanica.Banco

Terraform dos dados do ecossistema OficinaMecanica:

- **Azure SQL Database**: o SQL Server logico (`svsfiap`) e os 3 bancos que
  rodam nele (`OficinaMecanicaDb` do OS Service (o antigo monolito)
  [OficinaMecanica](../OficinaMecanica), `SegurancaDb` do
  [OficinaMecanica.Seguranca](../OficinaMecanica.Seguranca) e `BillingDb` do
  [OficinaMecanica.Billing](../OficinaMecanica.Billing)), cada um com um
  usuario SQL contido dedicado.
- **MongoDB Atlas (cluster M0 gratuito)** do
  [OficinaMecanica.Execucao](../OficinaMecanica.Execucao), com a connection
  string gravada no Key Vault por este repositorio.

Extraido do modulo `sqldb/` que vivia em
[OficinaMecanica.Infra](../OficinaMecanica.Infra) (repositorio irmao, que
centraliza todo o resto da infra do ecossistema) — ver `CLAUDE.md` para
detalhes da migracao.

> Estado: BillingDb, usuarios SQL e Atlas estao escritos e validados so com
> `terraform fmt`/`validate`; nada foi aplicado (ver `CLAUDE.md`).

Este repositorio e so Terraform — nao expoe nenhuma API HTTP propria (sem
Swagger/Postman aplicavel). As APIs que consomem esses bancos sao as dos
repositorios [OficinaMecanica](../OficinaMecanica),
[OficinaMecanica.Seguranca](../OficinaMecanica.Seguranca),
[OficinaMecanica.Billing](../OficinaMecanica.Billing) e
[OficinaMecanica.Execucao](../OficinaMecanica.Execucao).

## Ecossistema de microsservicos

O monolito original evoluiu para servicos independentes, cada um com
repositorio, banco, credencial de banco, pipeline e rota proprios, ligados so
em runtime (RabbitMQ para a Saga, HTTP/JWKS para a identidade). **Nenhum
servico acessa o banco de outro**: este repositorio provisiona os dados de
todos, mas cada credencial so alcanca o banco do seu servico.

| Repositorio | Papel | Dado provisionado aqui |
|-------------|-------|------------------------|
| [OficinaMecanica](../OficinaMecanica) (OS Service) | Cadastros, ordens de servico e **orquestrador da Saga** (OS aberta -> diagnostico -> orcamento -> aprovacao -> pagamento -> reparo -> finalizada, com compensacao em cada etapa) | `OficinaMecanicaDb` (usuario `app_os`) |
| [OficinaMecanica.Billing](../OficinaMecanica.Billing) | Orcamento e pagamento, integrado ao Mercado Pago | `BillingDb` (usuario `app_billing`) |
| [OficinaMecanica.Execucao](../OficinaMecanica.Execucao) | Fila de execucao, diagnostico e reparo | MongoDB Atlas M0, banco `execucao` (usuario `execucao_app`) |
| [OficinaMecanica.Seguranca](../OficinaMecanica.Seguranca) | Autenticacao/autorizacao: emite JWT (JSON Web Token) RS256 e expoe o JWKS | `SegurancaDb` (usuario `app_seguranca`) |
| [OficinaMecanica.Infra](../OficinaMecanica.Infra) | Terraform da plataforma (AKS, ACR, Key Vault, APIM, RabbitMQ, OIDC do GitHub Actions) | Monta as connection strings SQL no Key Vault com os usuarios criados aqui e concede ao CI deste repo a role no secret do Mongo |

```
Este repositorio (OficinaMecanica.Banco)                    Consumidor
----------------------------------------                    ----------
Azure SQL svsfiap
  |- OficinaMecanicaDb  <-- app_os ---------------------    OS Service
  |- SegurancaDb        <-- app_seguranca ---------------    Seguranca
  `- BillingDb          <-- app_billing ------------------   Billing
        (usuarios criados por sql/criar-usuarios.sql; connection strings no Key Vault
         kvfiap montadas pelo OficinaMecanica.Infra)

MongoDB Atlas M0 (projeto OficinaMecanica, cluster execucao)
  `- banco execucao     <-- execucao_app ----------------   Execucao
        (connection string gravada AQUI no Key Vault: execucao-mongo-connection-string)
```

## Diagramas

| Documento | Arquivo |
|-----------|---------|
| Modelo de Dados (ER - OficinaMecanicaDb e SegurancaDb; **anterior** ao `BillingDb` e ao MongoDB da Execucao, que ainda nao tem diagrama) | [docs/diagramas/modelo-de-dados.jpg](docs/diagramas/modelo-de-dados.jpg) |

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
| `data.azurerm_resource_group.existing` | `rgfiap` | Referencia por nome ao resource group do Infra (este repo nao o cria nem destroi) |
| `azurerm_mssql_server.this` | `svsfiap` | SQL Server logico (`svsfiap.database.windows.net`), TLS minimo 1.2, administrador `adminfiap` (so este repo e o CI usam; as apps nao) |
| `azurerm_mssql_database.this` | `OficinaMecanicaDb` | Banco do OS Service `OficinaMecanica` (tier sempre-gratis, criado via `az` e importado) |
| `azurerm_mssql_database.seguranca` | `SegurancaDb` | Banco do `OficinaMecanica.Seguranca` (serverless comum, 2 GB) |
| `azurerm_mssql_database.billing` | `BillingDb` | Banco do `OficinaMecanica.Billing` (serverless `GP_S_Gen5_2`, 0,5 vCore minimo, auto-pause de 60 min, teto de 5 GB) |
| `azurerm_mssql_firewall_rule.allow_azure_services` / `.client_ip` | `AllowAllWindowsAzureIps` / `ClientIp` | Libera servicos Azure (faixa `0.0.0.0`, nao a internet) + 1 IP de cliente opcional (`client_ip_address`, so se informado) |
| `mongodbatlas_project.this` | `OficinaMecanica` | Projeto proprio no Atlas |
| `mongodbatlas_advanced_cluster.execucao` | `execucao` | Cluster M0 gratuito (`TENANT`/`AZURE`, `US_EAST_2`) do `OficinaMecanica.Execucao`, com `prevent_destroy` |
| `random_password.execucao_mongo` | - | Senha de 32 caracteres alfanumericos do usuario do Atlas (so existe no state e no Key Vault) |
| `mongodbatlas_database_user.execucao_app` | `execucao_app` | `readWrite` somente no banco `execucao`, escopado ao cluster (nunca `atlasAdmin`) |
| `mongodbatlas_project_ip_access_list.aks_egress` | - | `/32` do IP de saida do AKS (sem `0.0.0.0/0`) |
| `data.azurerm_key_vault.this` | `kvfiap` | Referencia por nome ao Key Vault do Infra |
| `azurerm_key_vault_secret.execucao_mongo_connection_string` | `execucao-mongo-connection-string` | Connection string do Mongo, no `kvfiap` |

Usuarios SQL contidos (criados por `sql/criar-usuarios.sql` no CI, ou
localmente no bootstrap, nao por Terraform - o `azurerm` nao cria usuario
contido): `app_os` em `OficinaMecanicaDb`, `app_seguranca` em `SegurancaDb`,
`app_billing` em `BillingDb`, cada um `db_owner` so no proprio banco.

O resource group (`rgfiap`) e o Key Vault (`kvfiap`) sao provisionados e
gerenciados pelo `OficinaMecanica.Infra` — este repositorio so referencia
eles por nome (data source), nao cria nem destroi.

## Variaveis

Sem default (obrigatorias; entram por variavel de ambiente, nunca em
`terraform.tfvars` com valor sensivel):

| Variavel | Sensivel | Observacao |
|----------|----------|------------|
| `administrator_login_password` | sim | Senha do administrador do SQL Server |
| `sql_app_os_password`, `sql_app_seguranca_password`, `sql_app_billing_password` | sim | Mesmos nomes e mesmos valores do Infra; `validation` de 16 a 128 caracteres entre letras, digitos e `_ . @ # % ^ * + ~ -`, com maiuscula, minuscula e digito. Nenhum recurso as consome: servem so ao script SQL do CI e para o `plan` falhar cedo se o secret faltar |
| `atlas_org_id` | nao | 24 caracteres hexadecimais da organizacao no Atlas |
| `aks_egress_ip` | nao | Um unico IPv4 publico (IP de saida do AKS); CIDR, `0.0.0.0` e faixas privadas/loopback/link-local/CGNAT/multicast/reservadas sao recusados |
| `MONGODB_ATLAS_PUBLIC_KEY`, `MONGODB_ATLAS_PRIVATE_KEY` | sim | Nao sao variaveis Terraform: o provider `mongodbatlas` as le do ambiente |

Com default: `billing_database_name`, `billing_sku_name`, `billing_max_size_gb`,
`billing_min_capacity`, `billing_auto_pause_delay_in_minutes` (`BillingDb`,
`GP_S_Gen5_2`, 5, 0.5, 60), `key_vault_name` (`kvfiap`), `atlas_project_name`,
`atlas_cluster_name`, `atlas_region` (`OficinaMecanica`, `execucao`,
`US_EAST_2` - confirmar que a regiao oferece M0), `execucao_mongo_database_name`,
`execucao_mongo_username`, `execucao_mongo_secret_name` (`execucao`,
`execucao_app`, `execucao-mongo-connection-string`) e `client_ip_address`
(`null`).

## Rodando

```bash
cp terraform.tfvars.example terraform.tfvars
# preencher so o que nao e segredo; o resto entra por variavel de ambiente:
#   TF_VAR_administrator_login_password, TF_VAR_sql_app_os_password,
#   TF_VAR_sql_app_seguranca_password, TF_VAR_sql_app_billing_password,
#   TF_VAR_atlas_org_id, TF_VAR_aks_egress_ip,
#   MONGODB_ATLAS_PUBLIC_KEY, MONGODB_ATLAS_PRIVATE_KEY
#   (opcional, pra rodar o SQL daqui: TF_VAR_client_ip_address com o IP de quem executa)

terraform init
terraform plan
terraform apply

# depois do apply, por banco, com o go-sqlcmd conectado como administrador;
# as senhas vao por variavel de ambiente (SQLCMDPASSWORD e SenhaUsuario), nunca
# na linha de comando:
# sqlcmd -S <server_fqdn> -d <banco> -U <admin> -b -i sql/criar-usuarios.sql \
#   -v NomeUsuario=<app_...>
```

### Pre-requisitos que dependem de acao externa

- **Administrador humano no Azure** (`az login`) com `Key Vault Administrator`
  no `kvfiap` e `Storage Blob Data Contributor` no container do tfstate, para o
  primeiro apply (local).
- **Conta e organizacao no MongoDB Atlas**, uma **API key de organizacao** (par
  publico/privado; role minima esperada `Organization Project Creator`, a
  confirmar no primeiro apply) e o `atlas_org_id`.
- **`aks_egress_ip`**: IP publico de saida do AKS, copiado a mao do cluster (nao
  ha `terraform_remote_state`):
  `az aks show -g rgfiap -n aksfiap --query "networkProfile.loadBalancerProfile.effectiveOutboundIPs[].id" -o tsv`
  e depois `az network public-ip show --ids <id> --query ipAddress -o tsv`.
  Se o cluster for recriado, o IP muda e os pods da Execucao perdem acesso ao
  Mongo ate atualizar `TF_VAR_aks_egress_ip` e aplicar de novo.
- **go-sqlcmd** (mesma variante usada no CI) para criar os usuarios SQL no
  bootstrap local.
- **Para o CI**: a role `Key Vault Secrets Officer` do `github_oidc_banco`,
  escopada ao secret `execucao-mongo-connection-string` (concedida pelo Infra
  depois de o secret existir).

Como obter cada um esta no `CLAUDE.md` e no ADR 0002.

## CI/CD

O CI/CD ([.github/workflows/ci.yml](.github/workflows/ci.yml)) automatiza o
mesmo fluxo depois do bootstrap: `terraform plan` roda em todo PR contra
`main`/`release`, e `terraform apply` roda automaticamente em todo push (ou
disparo manual) nessas branches, seguido da criacao dos usuarios SQL (so se o
apply terminar com sucesso), autenticando via GitHub OIDC (identidade
`github_oidc_banco`, do Infra). O passo de SQL instala o go-sqlcmd pinado,
abre uma regra de firewall temporaria so com o IP do runner, roda
`sql/criar-usuarios.sql` nos tres bancos (ate 10 tentativas por banco) e remove
a regra (`if: always()`). O `validate` nao executa SQL.

Configurar no repositorio (Settings > Secrets and variables > Actions); sem
eles o `plan`/`apply` falha na validacao das variaveis:

| GitHub Secret | Variavel Terraform / uso | Sensivel |
|---------------|--------------------------|----------|
| `TF_VAR_ADMINISTRATOR_LOGIN_PASSWORD` | `administrator_login_password`; no passo de SQL vira `SQLCMDPASSWORD` | sim |
| `TF_VAR_SQL_APP_OS_PASSWORD` | `sql_app_os_password` | sim |
| `TF_VAR_SQL_APP_SEGURANCA_PASSWORD` | `sql_app_seguranca_password` | sim |
| `TF_VAR_SQL_APP_BILLING_PASSWORD` | `sql_app_billing_password` | sim |
| `TF_VAR_AKS_EGRESS_IP` | `aks_egress_ip` | nao (fica em secret por convencao do repo) |
| `TF_VAR_ATLAS_ORG_ID` | `atlas_org_id` | nao (idem) |
| `MONGODB_ATLAS_PUBLIC_KEY`, `MONGODB_ATLAS_PRIVATE_KEY` | variaveis de ambiente lidas pelo provider `mongodbatlas` | sim |

Variaveis (nao secrets): `AZURE_CLIENT_ID` (`terraform output banco_client_id`
do Infra), `AZURE_TENANT_ID` e `AZURE_SUBSCRIPTION_ID`.

## Ordem entre repositorios e bootstrap

Ordem em regime: **Banco -> Infra -> deploy dos servicos.** O Infra monta as
connection strings com os usuarios `app_*`; se ele aplicar antes de esses
usuarios existirem, OS Service e Seguranca (que hoje usam o admin) perdem a
conexao. O merge de um PR em `release`/`main` dispara `apply` com
`-auto-approve` nos dois repositorios, entao a ordem vale tambem para o merge.

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

## Decisao pendente: como o CI alcanca a API do Atlas

Antes do merge em `release` (que dispara o `apply` com `-auto-approve`) e preciso
decidir como o CI acessa a Administration API do Atlas: ela exige, por padrao,
uma **access list de IPs na API key**, e o runner hospedado do GitHub tem **IP
variavel**. Opcoes (ver ADR 0002):

- (a) liberar `0.0.0.0/0` na access list da **propria API key** (nao do cluster,
  que continua restrito ao `/32` do AKS), compensado pela role minima da key e
  por ela viver so em secret do GitHub;
- (b) desligar o requisito de access list da API na organizacao do Atlas;
- (c) listar as faixas do GitHub (`api.github.com/meta`) - inviavel, sao muitas
  e mudam toda semana;
- (d) runner proprio com IP fixo.

Ate escolher, o `plan`/`apply` pelo CI recebe 403 do Atlas. Como os recursos do
Atlas estao no state, todo `plan` de PR faz refresh no Atlas: um 403 persistente
trava o job `validate` e, como o `apply` tem `needs: validate`, bloqueia ate
mudancas so de SQL. A decisao e os secrets do Atlas precisam estar prontos antes
do merge.

## Atlas M0: limites e riscos

512 MB (inclui indices), 500 conexoes, ~100 operacoes/s (estrangula, nao
rejeita), 10 GB de entrada/saida por 7 dias, 1 cluster gratuito por projeto,
pausa apos 30 dias sem conexoes. O cluster nao e modificavel depois de criado:
trocar nome ou regiao recria o cluster e apaga os dados (por isso
`prevent_destroy`). Rotacionar a senha do usuario do Atlas:
`terraform apply -replace=random_password.execucao_mongo` e reiniciar os pods
da Execucao. Ainda nao verificado no Atlas real: transacoes multi-documento no
M0 (necessarias ao outbox do MassTransit sobre MongoDB), a regiao `US_EAST_2`
oferecer M0 e a criacao do cluster pelo provider 2.x (ver ADR 0002).

## Infraestrutura relacionada

Todo o resto da infra do ecossistema (AKS, ACR, Key Vault, Function App,
APIM, RabbitMQ, OIDC do GitHub Actions) vive em
[OficinaMecanica.Infra](../OficinaMecanica.Infra) — ver o `CLAUDE.md` de la
pra entender como as connection strings deste banco chegam no Key Vault sem
os dois repositorios compartilharem state. Em resumo, o contrato entre os dois:

- Nomes: bancos `OficinaMecanicaDb`/`SegurancaDb`/`BillingDb`, usuarios
  `app_os`/`app_seguranca`/`app_billing` e as tres variaveis de senha com os
  mesmos nomes nos dois repos; o Infra grava `sql-connection-string`,
  `seguranca-sql-connection-string` e `billing-sql-connection-string` no
  `kvfiap` (com `Initial Catalog`, porque usuario contido nao conecta no `master`).
- O secret `execucao-mongo-connection-string` e gravado **aqui** (o host do Atlas
  so existe apos criar o cluster) e lido pela Execucao via CSI Secrets Store.
- O Infra concede ao `github_oidc_banco` `Reader` no resource group,
  `Contributor` no SQL Server e `Key Vault Secrets Officer` escopado **so** a esse
  secret (a identidade tem credencial de `pull_request`).
- Sem `terraform_remote_state`: nomes e `aks_egress_ip` sao copiados a mao.

## Stack Tecnologica

| Categoria | Tecnologia | Versao |
|-----------|-----------|--------|
| IaC | Terraform (providers `azurerm ~> 4.0`, `mongodbatlas ~> 2.21`, `random ~> 3.6`) | >= 1.5 (CI usa 1.15.7) |
| Banco relacional | Azure SQL Database (`OficinaMecanicaDb` sempre-gratis, `SegurancaDb` e `BillingDb` serverless) | — |
| Banco de documentos | MongoDB Atlas M0 (hospedado no Azure) | — |
| CI/CD | GitHub Actions + OIDC (Federated Identity Credential, sem client secret) | — |
