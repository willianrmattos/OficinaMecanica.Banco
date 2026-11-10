# ADR 0002: MongoDB Atlas M0 provisionado por Terraform neste repositorio

## Status
**Atualizacao em 2026-11-10:** o cluster Atlas M0 foi criado (regiao EUROPE_NORTH) pelo root `atlas/`, aplicado so localmente; "nada foi aplicado" e "validacao no Atlas real ainda
pendente", abaixo, descrevem o momento da decisao.

Aceito. Parcialmente substituido pelo ADR 0004: a decisao de provisionar o M0
por Terraform neste repositorio continua valendo, mas o Atlas vive num root
separado (`atlas/`, state `atlas.tfstate`) aplicado so localmente, e o CI nao o
alcanca. Validacao no Atlas real ainda pendente: o codigo foi so validado com
`terraform fmt` e `terraform validate`, nada foi aplicado (ver "Pendencias de
validacao" em Consequencias).

## Contexto
O `OficinaMecanica.Execucao` (fila de execucao, diagnostico e reparo) precisa
de um banco proprio, NoSQL, independente dos bancos SQL dos outros servicos
(requisito de independencia: banco, credencial de banco, segredos e rota
dedicados por servico). O codigo dele ja assume MongoDB: a fila e consumida
por claim atomico (substituicao do documento filtrada pela versao, com retentativa em conflito) e o outbox do MassTransit
(`MassTransit.MongoDb` 8.5.12) exige transacao multi-documento, ou seja,
replica set. A aplicacao le `ConnectionStrings:MongoDb` e `MongoDb:Database`
(padrao `execucao`).

O projeto usa tiers gratuitos sempre que existem, e o MongoDB Atlas oferece o
cluster M0 gratuito, hospedado no Azure, como replica set de 3 nos fixo.
Faltava decidir onde esse cluster e o segredo de acesso a ele sao provisionados, ja que
nenhum repositorio de aplicacao tem Terraform proprio.

## Decisao
Provisionar o Atlas neste repositorio (`OficinaMecanica.Banco`), no root Terraform
separado `atlas/` (state proprio, `atlas.tfstate`, aplicado so localmente; ver
ADR 0004), com o provider `mongodb/mongodbatlas` (`~> 2.21`, resolvido 2.21.0):

- `mongodbatlas_project`: projeto proprio, para isolar usuarios e IP access
  list do restante da organizacao e porque o limite do M0 e 1 cluster
  gratuito por projeto.
- `mongodbatlas_advanced_cluster`: `REPLICASET`, `provider_name = "TENANT"`,
  `backing_provider_name = "AZURE"`, `instance_size = "M0"`, regiao pela
  variavel `atlas_region` (padrao `EUROPE_NORTH`). Com `prevent_destroy`.
- `mongodbatlas_database_user` `execucao_app`: role `readWrite` SOMENTE no
  banco `execucao` (nunca `atlasAdmin`), escopado ao cluster. A senha e gerada
  por `random_password` (32 caracteres alfanumericos): ninguem a conhece, ela
  so existe no state e no Key Vault. Rotacao: `terraform
  -chdir=atlas apply -replace=random_password.execucao_mongo`, seguido de
  reinicio dos pods do Execucao para ler o novo valor.
- `mongodbatlas_project_ip_access_list`: um unico `/32`, o IP publico de saida
  do AKS (`aks_egress_ip`, sem valor padrao). Nao ha `0.0.0.0/0`.
- `azurerm_key_vault_secret` `execucao-mongo-connection-string` no `kvfiap`,
  gravado por este proprio repositorio (pelo root `atlas/`) com a string
  `mongodb+srv://execucao_app:<senha>@<host>/execucao?authSource=admin&retryWrites=true&w=majority`.
  O `OficinaMecanica.Infra` so le o secret (SecretProviderClass do Execucao) e
  nunca ve a senha em variavel nem em output.

### Por que no Banco e nao no Infra
- Seguir o ADR 0001: dados vivem num state proprio. O M0 nao e modificavel
  depois de criado (a API so cria), entao qualquer diff que force substituicao
  (nome, regiao) apaga os dados; isso nao pode estar no mesmo state de AKS e
  APIM.
- O Infra nao precisa de conta, provider nem credencial do Atlas.
- O segredo nasce junto do recurso que ele descreve, sem passar por variavel
  nem por `terraform_remote_state` (que o ADR 0001 proibe).

### Dependencia com o Infra e bootstrap
Atualizacao (ADR 0004): este trecho descrevia o `apply` do CI gravando o secret
com a identidade `github_oidc_banco`, que recebia do Infra a role `Key Vault
Secrets Officer` escopada so a esse secret. Isso deixou de existir: o Atlas e
aplicado so localmente, o CI nao o aplica nem o le, e o Infra nao concede mais
essa role. O que vale hoje:

O `atlas/` e aplicado da maquina de um administrador humano (`Key Vault
Administrator` no `kvfiap`, mais a API key do Atlas). O `OficinaMecanica.Infra`
so referencia o secret pelo nome (SecretProviderClass do Execucao). O `atlas/`
so precisa que o `kvfiap` ja exista, porque o referencia por nome (data source).

O bootstrap, portanto, e:

1. Aplicar o root principal **localmente** na primeira vez, com um administrador
   humano: cria o `BillingDb`.
2. Criar os usuarios SQL (ADR 0003): rodando `sql/criar-usuarios.sql` local logo
   em seguida, ou pelo primeiro apply bem-sucedido do CI. Se o `Terraform Apply`
   do CI falhar, os passos de SQL sao pulados.
3. Aplicar o `atlas/` **localmente**: cria o projeto, o cluster M0, o usuario, a
   IP access list e o secret.
4. O Infra (CI) cria as connection strings.

O `atlas/` precisa estar aplicado antes do **deploy do Execucao** (o pod le o
secret pelo SecretProviderClass); nao e pre-requisito do apply do Infra. A ordem
Banco -> Infra vem dos usuarios SQL (ADR 0003). Se o secret for apagado do Key
Vault, aplicar o `atlas/` de novo o recria.

### Rede: IP de saida do AKS
O M0 nao suporta private endpoint nem VNet peering, entao a allowlist por IP e o
unico controle de rede. Como obter o valor de `aks_egress_ip`:

```bash
az aks show -g rgfiap -n aksfiap --query "networkProfile.loadBalancerProfile.effectiveOutboundIPs[].id" -o tsv
az network public-ip show --ids <id retornado> --query ipAddress -o tsv
```

Alternativa de conferencia: rodar um pod temporario no cluster
(`kubectl run -it --rm ip --image=curlimages/curl -- curl -s https://api.ipify.org`).
Se o cluster for recriado, ou o load balancer de saida for trocado, o IP muda:
os pods passam a falhar com timeout de selecao de servidor ate `aks_egress_ip`
ser atualizado (`TF_VAR_aks_egress_ip`, no ambiente de quem aplica o `atlas/`) e
o apply local do `atlas/` rodar de novo. A variavel aceita um unico IP; se o AKS
passar a ter mais de um IP de saida, ela precisa virar lista.

### Credenciais do Atlas para o Terraform
API key de organizacao (par publico/privado) pelas variaveis de ambiente
`MONGODB_ATLAS_PUBLIC_KEY` e `MONGODB_ATLAS_PRIVATE_KEY` (ou, se migrar para
service account, `MONGODB_ATLAS_CLIENT_ID`/`MONGODB_ATLAS_CLIENT_SECRET`), mais
a variavel nao secreta `atlas_org_id`. Nada disso vai para arquivo: entram pelo
ambiente de quem aplica o `atlas/`, localmente. A role minima esperada da key e
`Organization Project Creator`, que cria o projeto; no primeiro apply e preciso
confirmar que a key criadora ganha permissao suficiente sobre o projeto novo
(cluster, usuario, IP access list) e, se nao ganhar, ajustar a role.

Atualizacao (ADR 0004): a Administration API do Atlas exige, por padrao, uma
access list de IPs na API key, e o runner hospedado do GitHub tem IP variavel.
Este ADR deixava em aberto como o CI a alcancaria, com quatro opcoes: (a)
`0.0.0.0/0` na access list da propria API key, (b) desligar o requisito de
access list na organizacao, (c) listar as faixas do GitHub, (d) runner proprio
com IP fixo. Foi resolvido pelo ADR 0004: o CI nao alcanca o Atlas. O Atlas
recusa a opcao (a) (HTTP 400 em 2026-11-09), a (c) e inviavel e a (b) e a (d)
foram rejeitadas; a key fica presa ao IP do administrador, que aplica o `atlas/`
localmente.

## Consequencias
### Positivas
- Independencia do Execucao: projeto, cluster, banco e credencial proprios no
  Atlas, com menor privilegio (`readWrite` em um unico banco, escopado ao
  cluster, acessivel so do IP do AKS).
- Nenhum segredo em arquivo versionado nem em secret do CI; a API key do Atlas
  vive so no ambiente de quem aplica o `atlas/`, e a senha do banco nunca e
  digitada por ninguem.
- A connection string e reproduzivel: recriar o ambiente recria o secret.

### Negativas
- O apply do `atlas/` depende de um SaaS externo (conta e API key do Atlas) e dos
  providers `mongodbatlas` e `random`; o root principal nao depende de nenhum
  deles.
- A senha e a connection string ficam em texto no state do `atlas/`
  (`atlas.tfstate`, storage account `stfiap`, acesso por Azure AD) alem do Key
  Vault.
- O M0 nao e modificavel: nome ou regiao diferentes recriam o cluster e perdem
  os dados, por isso o `prevent_destroy` (o apply falha em vez de destruir).
- O IP do AKS e acoplamento manual entre dois repositorios (sem
  `terraform_remote_state`): se mudar no Infra, precisa ser atualizado no
  `atlas/`.
- O `atlas/` fica fora do `plan` de PR e do `apply` automatico (ADR 0004): so um
  administrador o aplica, localmente, e o CI so garante que o codigo continua
  valido (`fmt` e `validate`). O CI nao tem credencial do Atlas.
- O apply do `atlas/` nao e automatizavel pelo CI: exige uma execucao local com
  administrador do Key Vault e uma API key do Atlas cuja access list inclua o IP
  da maquina.
- O `apply` do CI (root principal) nao pode ser cancelado no meio: a
  `concurrency` so cancela execucoes de PR, porque cancelar a criacao de um
  recurso demorado (um banco serverless leva minutos) pode deixar um recurso
  orfao fora do state.

### Limites do M0 que afetam o Execucao
- 512 MB (0,5 GB, documentos e indices), 500 conexoes, 100 operacoes de
  leitura/escrita por segundo (acima disso o Atlas estrangula, nao rejeita),
  10 GB de entrada e 10 GB de saida a cada 7 dias, 100 bancos e 500 colecoes.
- Como o `MongoClient` e singleton (um pool por pod), 500 conexoes cobrem as
  poucas replicas previstas; o teto real a vigiar e o de operacoes por segundo.
- O outbox `MassTransit.MongoDb` custa cerca de 37,5 operacoes por mensagem
  (medido no spike do outbox), o que da um teto de ~2,7 mensagens/s no M0. O
  fallback do spike (outbox embutido no documento + relay) custa ~4,2
  operacoes por mensagem.
- Inatividade: o Atlas pausa o cluster gratuito apos 30 dias sem conexoes.

### Pendencias de validacao (nao verificadas)
- Transacoes e replica set no M0: a pagina oficial de limites e silenciosa sobre
  transacoes multi-documento. O M0 e um replica set de 3 nos, entao e esperado
  funcionar, mas o spike do outbox rodou em Mongo 7 local; o teste real de transacao
  + consumer no Atlas M0 precisa acontecer antes de fechar a escolha do outbox
  (resultados do spike na secao abaixo). Se o M0 rejeitar ou estrangular
  transacoes, usar o fallback ja implementado.
- Regiao: o padrao e `EUROPE_NORTH` (Irlanda), escolhida pelo dono do projeto
  (conta do Atlas em regiao europeia). Verificada em 2026-11-09: o apply do
  `atlas/` criou o M0 ali, entao a regiao oferece o tier gratuito. Custo: o
  resource group do AKS fica em `northcentralus`, entao cada operacao
  Execucao -> Mongo paga latencia transatlantica (ordem de 100 ms).
  `US_EAST_2` (Virginia, proxima do AKS) e `CANADA_CENTRAL` (Toronto) seguem
  como alternativas, sem confirmacao de M0. A coluna "Free" da tabela de
  regioes Azure da documentacao do Atlas e a fonte de verdade, mas os
  marcadores dela nao vem na leitura automatizada.
- Role minima da API key (descrita acima). O requisito de access list da
  Administration API esta resolvido pelo ADR 0004.
- O provider `mongodbatlas` 2.x foi escolhido pela versao atual do registro; a
  sintaxe (`replication_specs` como lista de atributos) foi checada pelo
  `validate`, e a criacao do M0 foi confirmada no apply de 2026-11-09 (cluster
  `execucao` em `EUROPE_NORTH`, estado `IDLE`).

### Resultados do spike do outbox
Antes de escrever o Execucao, um spike descartavel validou o `MassTransit.MongoDb`
8.5.12 com RabbitMQ contra um MongoDB 7 em replica set local (34 de 34 testes da
suite principal). O Atlas M0 real e o Mongo 8.0 NAO foram verificados. O resumo
abaixo e autocontido; o que o spike concluiu e o que o Banco e o Execucao
precisam manter:

| Item | Resultado |
|------|-----------|
| Consumer grava o documento e publica o evento pelo outbox na mesma transacao Mongo | Passou, com condicoes: falha depois da escrita deixa 0 documentos, 0 mensagens no outbox e 0 eventos; 3 entregas do mesmo `MessageId` executam o handler 1 vez e geram 1 evento; 5 copias concorrentes geram 1 evento |
| Caminho HTTP (handler -> unidade de trabalho, UoW) | Passou: documento e evento gravados atomicamente; falha injetada resulta em 500, documento intacto e 0 eventos. A UoW faz o commit explicito e retenta `TransientTransactionError` com backoff |
| Outbox embutido no documento (`eventosPendentes`) + relay (fallback) | Passou, mas nao recomendado: funciona ate em Mongo standalone e custa ~4,2 operacoes por mensagem (contra ~37,5 do outbox do MassTransit); sem lease/inbox o relay duplica entregas (3 a 4 vezes com 4 relays) |
| Mongo standalone x replica set | Parcial: standalone falha com `Standalone servers do not support transactions` (o outbox do MassTransit nao funciona, o fallback sim); o outbox exige replica set, como o M0 (3 nos) |
| Capacidade no M0 (so documentacao) | 500 conexoes, 100 operacoes/s, 0,5 GB, estrangula em vez de rejeitar; com ~37,5 operacoes por mensagem o teto e ~2,7 mensagens/s |

Condicoes validadas para usar o outbox do MassTransit (e nao o fallback):
- `UseMessageRetry` ANTES de `UseMongoDbOutbox`: sem o retry, 18 a 20 de 40
  duplicatas concorrentes caem na fila de erro; com `Immediate(3)`, nenhuma.
- Pre-criar as colecoes `inbox.states`, `outbox.messages` e `outbox.states` e o
  indice unico `{MessageId, ConsumerId}` do inbox antes de o bus subir (o servico
  de limpeza do inbox cria o indice em segundo plano e colide com a primeira
  mensagem).
- Todo caminho HTTP passa pela UoW com commit explicito da transacao: nao existe
  "SaveChanges", e publicar sem `CommitTransaction` perde o evento em silencio. O
  claim da fila, de preferencia, fora de transacao (dentro funciona, com
  conflitos e retry).
- `WaitUntilStarted = true` e janela de deduplicacao de 30 minutos, mantendo a
  idempotencia natural do dominio como segunda defesa.

Nao verificado pelo spike: Atlas M0 real e Mongo 8.0; queda do processo entre o
commit e a entrega; broker indisponivel; varias replicas com entrega concorrente;
politicas de retry alem de `Immediate(3)`; `maxPoolSize` no M0.

## Alternativas consideradas
- **Atlas dentro do `OficinaMecanica.Infra`**: concentraria mais Terraform num so
  lugar, mas misturaria o recurso mais sensivel (dados, nao recriavel) com AKS e
  APIM no mesmo state e exigiria dar ao Infra credenciais do Atlas.
- **Cluster criado a mao na interface do Atlas**: nao reproduzivel, sem
  versionamento da allowlist nem do usuario, e o segredo teria de ser copiado a
  mao para o Key Vault.
- **Connection string como output sensivel lida pelo Infra**: exigiria
  `terraform_remote_state` entre os repositorios, rejeitado no ADR 0001.
- **Senha do usuario do Atlas como variavel (`TF_VAR_*`)**: mais um secret para
  manter em dois lugares sem ganho, ja que so este repositorio usa a senha.
- **`0.0.0.0/0` na allowlist do cluster**: elimina o problema do IP do AKS, mas
  expoe o cluster a internet inteira protegido so por senha; rejeitado.
- **MongoDB dentro do AKS (StatefulSet)**: o no unico do cluster nao tem CPU
  sobrando e passaria a exigir operacao de banco (backup, replica set).
- **Azure Cosmos DB for MongoDB**: o projeto decidiu por Atlas, e a semantica de
  transacao/outbox do `MassTransit.MongoDb` foi validada contra MongoDB de
  verdade, nao contra a API de compatibilidade.
