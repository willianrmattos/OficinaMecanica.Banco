# ADR 0004: Atlas aplicado so localmente, fora do CI

## Status
Aceito em 2026-11-09. Substitui parcialmente o ADR 0002: a escolha do MongoDB
Atlas M0 e do Terraform deste repositorio como provisionador continua valendo,
mas o ADR 0004 define onde o Atlas e aplicado (root `atlas/`, so localmente) e
encerra a decisao pendente sobre como o CI alcancaria a API do Atlas (o CI nao a
alcanca). Nada foi aplicado ainda: o root `atlas/` foi validado com `fmt`, `validate` e um
`plan` local so de leitura (6 recursos a criar, nenhum a alterar ou destruir).

## Contexto
O ADR 0002 colocou o Atlas (`atlas.tf`) no mesmo root e no mesmo state
(`banco.tfstate`) do SQL Server e dos bancos. O CI roda `terraform plan` em todo
PR e `terraform apply -auto-approve` no merge em `main`/`release`, entao ele
passou a precisar falar com a Administration API do Atlas.

Essa API exige, por padrao, uma access list de IPs na API key, e o runner
hospedado do GitHub tem IP variavel. O Atlas **recusa** `0.0.0.0/0` na access
list de uma API key (testado em 2026-11-09: HTTP 400
`CANNOT_ADD_IP_ADDRESS_TO_API_KEY_ACCESS_LIST`, "The address 0.0.0.0/0 cannot be
added to access lists"). Isso eliminou a opcao (a) do ADR 0002 (liberar
`0.0.0.0/0` na propria key) e deixou o CI sem forma segura de alcancar o Atlas.

O estrago ia alem do Atlas: como os recursos dele estavam no state do root
principal, todo `plan` de PR fazia refresh no Atlas, e um 403 persistente
travava o job `validate` e, pelo `needs`, o job `apply`, inclusive para mudancas
que so tocam SQL. E o `apply` e automatico (`-auto-approve`) no merge.

Alem disso, o cluster M0 nao e modificavel depois de criado (a API so cria):
depois do primeiro apply, o CI nao tem nada a agregar no Atlas.

## Decisao
Tirar o Atlas do CI:

1. **Root separado**: o `atlas.tf` virou a pasta `atlas/`, um root Terraform
   independente, com `main.tf`, `variables.tf`, `outputs.tf`, `providers.tf`,
   `versions.tf`, `backend.tf`, `terraform.tfvars.example` e `README.md`. O state
   e proprio: `atlas.tfstate`, na mesma storage account `stfiap` e no mesmo
   container `tfstate` (o root principal continua em `banco.tfstate`).
2. **Root principal so com SQL**: SQL Server, `OficinaMecanicaDb`,
   `SegurancaDb`, `BillingDb`, regra de firewall e os outputs de SQL. O unico
   provider dele e o `azurerm` (`mongodbatlas` e `random` ficam so no `atlas/`).
   As variaveis `atlas_*`, `execucao_mongo_*`, `key_vault_name` e `aks_egress_ip`
   existem so em `atlas/variables.tf`.
3. **`atlas/` aplicado so localmente**, da maquina de um administrador: `az
   login` com `Key Vault Administrator` no `kvfiap` e `Storage Blob Data
   Contributor` no container do tfstate, e uma API key de organizacao do Atlas
   (role `Organization Project Creator`) cuja access list inclua o IP dessa
   maquina. Comandos: `cd atlas; terraform init; terraform plan; terraform
   apply`, com `MONGODB_ATLAS_PUBLIC_KEY`, `MONGODB_ATLAS_PRIVATE_KEY`,
   `TF_VAR_atlas_org_id` e `TF_VAR_aks_egress_ip` no ambiente. Ele cria o projeto
   `OficinaMecanica`, o cluster M0 `execucao` (provedor `AZURE`, regiao
   `US_EAST_2`, com `prevent_destroy`), o usuario `execucao_app` (`readWrite` so
   no banco `execucao`), a IP access list com o IP de saida do AKS (`/32`), o
   `random_password` e grava a connection string no secret
   `execucao-mongo-connection-string` do Key Vault.
4. **O CI nao aplica nem le o `atlas/`**: o `plan` e o `apply` cobrem so o root
   principal. O CI so valida o codigo: `terraform fmt -check -recursive` (que
   cobre o `atlas/`) e o passo "Terraform Validate (atlas)", com `init
   -backend=false` e `validate`, sem credenciais e sem tocar no state.
5. **A API key continua presa ao IP do administrador**: nenhuma access list de
   API key fica aberta para a internet.

## Consequencias
### Positivas
- O CI nunca fala com o Atlas: um 403 ou uma indisponibilidade do SaaS nao trava
  mais o `validate` nem o `apply` de mudancas de SQL.
- A API key do Atlas vive so no ambiente de quem aplica o `atlas/`: nenhum secret
  do Atlas no GitHub e nenhuma access list de key aberta para o mundo.
- A identidade `github_oidc_banco` deixa de ter a role `Key Vault Secrets Officer`
  no secret `execucao-mongo-connection-string`. Como essa identidade tem
  credencial de `pull_request`, o raio de impacto dela encolhe: nenhum workflow
  de PR roda com um token capaz de escrever esse secret.
- A senha e a connection string do Mongo passam a viver so em `atlas.tfstate`, e
  nao mais no state do root principal.
- O root principal deixa de depender de um SaaS externo e de dois providers
  (`mongodbatlas`, `random`).

### Negativas
- O `atlas/` fica fora do `plan` de PR e do `apply` automatico: mudancas so entram
  quando um administrador as aplica localmente, e o CI nao detecta drift no
  Atlas. O CI so garante que o codigo continua valido (`fmt` e `validate`); erro
  que so aparece com a API real (provider, permissao, regiao) so aparece no
  `plan`/`apply` local.
- Depende de uma pessoa com `az login` administrador e uma API key do Atlas cuja
  access list tenha o IP da maquina dela; se o IP mudar, a access list da key
  precisa ser atualizada.
- Como o M0 nao e modificavel, o `atlas/` so e aplicado de verdade na criacao, na
  rotacao da senha e quando o IP de saida do AKS muda; fora isso e raro mexer
  nele.
- Dois roots no mesmo repositorio: `terraform` na raiz nao enxerga o Atlas, e o
  `atlas/` precisa de `cd atlas` ou `terraform -chdir=atlas ...`.
- O IP do AKS continua sendo acoplamento manual entre dois repositorios (sem
  `terraform_remote_state`, ADR 0001): se mudar, atualizar `TF_VAR_aks_egress_ip`
  e aplicar o `atlas/` de novo, localmente.
- Rotacionar a senha do usuario do Atlas tambem e feito localmente:
  `terraform -chdir=atlas apply -replace=random_password.execucao_mongo`, seguido
  de reinicio dos pods do Execucao.

### Ordem de aplicacao
- **Banco -> Infra continua valendo**, por causa dos usuarios SQL dedicados
  (`app_os`, `app_seguranca`, `app_billing`, ADR 0003): se o Infra aplicar antes
  de eles existirem, OS Service e Seguranca perdem a conexao com o banco.
- **`atlas/` antes do deploy do Execucao**: o pod le o secret
  `execucao-mongo-connection-string` pelo SecretProviderClass, entao o secret
  precisa existir antes do deploy. Nao e pre-requisito do apply do Infra. O
  `atlas/` so precisa que o Key Vault `kvfiap` (que o Infra cria) ja exista,
  porque o referencia por nome.
- O Infra deixa de conceder ao `github_oidc_banco` a role no secret do Mongo, e o
  secret nao precisa mais existir antes de nenhum apply do Infra. Se o secret for
  apagado do Key Vault, `terraform -chdir=atlas apply` o recria.

### Secrets do GitHub que deixam de ser necessarios
`TF_VAR_AKS_EGRESS_IP`, `TF_VAR_ATLAS_ORG_ID`, `MONGODB_ATLAS_PUBLIC_KEY` e
`MONGODB_ATLAS_PRIVATE_KEY` podem ser removidos das configuracoes do repositorio
(o CI nao os le mais). Continuam: `TF_VAR_ADMINISTRATOR_LOGIN_PASSWORD`,
`TF_VAR_SQL_APP_OS_PASSWORD`, `TF_VAR_SQL_APP_SEGURANCA_PASSWORD`,
`TF_VAR_SQL_APP_BILLING_PASSWORD` e as variaveis `AZURE_CLIENT_ID`,
`AZURE_TENANT_ID` e `AZURE_SUBSCRIPTION_ID`.

## Alternativas consideradas
- **`0.0.0.0/0` na access list da API key** (opcao (a) do ADR 0002): o Atlas
  recusa (HTTP 400, ver Contexto).
- **Dois blocos `/1` (`0.0.0.0/1` e `128.0.0.0/1`)**: rejeitada. Cobre a internet
  inteira por uma via que o Atlas aceita, ou seja, contorna uma trava deliberada
  dele e deixa a chave aberta ao mundo.
- **Desligar o requisito de access list na organizacao do Atlas**: rejeitada.
  Afrouxa o requisito para todas as chaves da organizacao, inclusive a de
  administracao.
- **Listar as faixas do GitHub** (`api.github.com/meta`, opcao (c) do ADR 0002):
  inviavel, sao muitas e mudam toda semana.
- **Runner proprio com IP fixo** (por exemplo no AKS, com IP de saida fixo):
  rejeitada por ora. O repositorio e publico, entao um runner proprio exige
  travas contra codigo de PR rodando na infraestrutura, e o no do AKS e unico.
- **Tirar o Atlas do CI** (escolhida): o M0 nao muda depois de criado, entao o CI
  nao perde nada de util, e a API key continua presa ao IP do administrador.
