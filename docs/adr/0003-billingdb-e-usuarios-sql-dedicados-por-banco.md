# ADR 0003: BillingDb e usuarios SQL dedicados por banco

## Status
**Atualizacao em 2026-11-10:** o BillingDb e os usuarios SQL dedicados foram aplicados em 2026-11-09; "nada foi aplicado ainda", abaixo, descreve o momento da decisao.

Aceito. Nada foi aplicado ainda: o Terraform foi validado so com `fmt` e
`validate`, e o script T-SQL so teve a sintaxe verificada por parser offline
(nenhum SQL foi executado contra servidor nenhum).

## Contexto
O ecossistema passa a ter tres servicos com banco SQL: `OficinaMecanica` (OS
Service, `OficinaMecanicaDb`), `OficinaMecanica.Seguranca` (`SegurancaDb`) e o
novo `OficinaMecanica.Billing` (orcamentos e pagamentos), que precisa de um
banco proprio. O requisito de independencia dos servicos pede credencial de
banco dedicada, com acesso somente ao banco do servico, e nunca o administrador
do servidor nas aplicacoes.

Hoje os bancos moram no mesmo servidor logico `svsfiap`, e as connection
strings guardadas no Key Vault pelo `OficinaMecanica.Infra` usam o
administrador do servidor, o que da a cada servico acesso a todos os bancos.

## Decisao
1. **`BillingDb`** no mesmo servidor `svsfiap`, serverless (`GP_S_Gen5_2`, 0,5
   vCore minimo, auto-pause de 60 minutos, teto de 5 GB), mesmo padrao do
   `SegurancaDb` (`azurerm_mssql_database.billing`, variaveis `billing_*`). O
   servidor logico continua compartilhado de proposito: um servidor novo
   reabriria o risco de regiao/capacidade ja enfrentado (ver `main.tf` e o
   `CLAUDE.md`), e o tier sempre-gratis so vale uma vez por assinatura (ja usado
   pelo `OficinaMecanicaDb`).
2. **Um usuario SQL contido por banco**, nunca o administrador: `app_os` em
   `OficinaMecanicaDb`, `app_seguranca` em `SegurancaDb` e `app_billing` em
   `BillingDb`, cada um membro de `db_owner` apenas no proprio banco. Usuario
   contido nao tem login no `master`, entao a credencial nao serve para nenhum
   outro banco do servidor; a connection string precisa trazer o banco
   (`Initial Catalog`).
3. **Criacao por script SQL versionado**, `sql/criar-usuarios.sql`, executado
   pelo job `apply` do CI depois do `terraform apply` (os bancos ja existem), uma
   vez por banco, conectado como administrador do servidor. O script e
   idempotente: se o usuario existe, so sincroniza a senha (e assim a rotacao e
   trocar o secret e repetir o job); se ja e `db_owner`, nao repete. O nome do
   usuario entra por `-v` e a senha por variavel de ambiente do processo do
   go-sqlcmd (que resolve a variavel do script a partir do ambiente), nunca
   literal no arquivo nem na linha de comando. O job `validate` nao executa
   SQL. No job `apply`, se o `Terraform Apply` falhar, os passos de SQL sao
   pulados: os usuarios so nascem numa execucao em que o apply termina. O mesmo
   script pode ser rodado localmente (via preferencial no bootstrap, abaixo).
4. **Senhas** em variaveis sensiveis `sql_app_os_password`,
   `sql_app_seguranca_password` e `sql_app_billing_password` (secrets do GitHub
   `TF_VAR_SQL_APP_*_PASSWORD`). Sao os MESMOS nomes usados pelo
   `OficinaMecanica.Infra`, que as usa para montar as connection strings no Key
   Vault. Este repositorio as declara so para o `validation` (16 a 128
   caracteres seguros, com maiuscula, minuscula e digito, sem aspas, ponto e
   virgula, igual ou barra invertida: entram num literal T-SQL e numa connection
   string): o `plan`, que tambem roda em PR, falha cedo se o secret faltar ou
   estiver fora do padrao, em vez de o `apply` terminar e o passo de SQL falhar
   depois. Nenhum recurso do Terraform as consome.
5. **Acesso do runner ao SQL**: regra de firewall temporaria so com o IP publico
   do runner (`/32`, `ci-runner-<run_id>-<tentativa>`), criada com `az sql server
   firewall-rule create` antes do SQL e removida em passo final com `if:
   always()` (roda tambem se o job falhar ou for cancelado). A identidade
   `github_oidc_banco` ja tem `Contributor` no SQL Server, suficiente para isso.
   O passo de SQL tenta ate 10 vezes com 30 s de intervalo, porque o firewall do
   Azure SQL pode levar alguns minutos para propagar a regra e o banco
   serverless pode estar pausado (a primeira conexao o retoma e falha enquanto
   ele sobe).
6. **Ordem de aplicacao**: Banco primeiro (bancos e usuarios), Infra depois
   (connection strings com esses usuarios no Key Vault), deploy dos servicos por
   ultimo. Se o Infra aplicar antes de os usuarios existirem, OS Service (o antigo monolito) e
   Seguranca (que hoje usam o administrador) perdem a conexao.

   Bootstrap (primeira vez), coerente com os ADRs 0002 e 0004: (a) aplicar o
   root principal do Banco localmente com administrador humano, o que cria
   `BillingDb`; (b) criar os usuarios SQL, preferencialmente rodando
   `sql/criar-usuarios.sql` local logo depois de (a), para que existam antes de
   o Infra trocar as connection strings dos servicos que ja rodam (a via pelo
   CI, no primeiro apply bem-sucedido, so serve se nenhum servico em uso
   depender deles antes disso); (c) aplicar o `atlas/` localmente (Atlas e
   secret do Mongo; precisa estar pronto antes do deploy do Execucao, nao antes
   do Infra); (d) o Infra (CI) cria as connection strings.

### Por que `db_owner` e nao menos
O mesmo usuario e usado pela aplicacao e pelo passo de migrations do CI de cada
servico (`dotnet ef database update`, que le a connection string do Key Vault).
Uma migration do EF executa `CREATE`/`ALTER`/`DROP` de tabela, indice e chave
estrangeira, `sp_rename` e escreve em `__EFMigrationsHistory`; as tabelas de
saga, outbox e inbox do MassTransit tambem nascem por migration. `db_owner` no
proprio banco e o conjunto de permissoes que cobre isso sem depender de uma
lista de permissoes por tipo de migration. Os papeis `db_ddladmin` +
`db_datareader` + `db_datawriter` cobrem a maior parte, mas nao ha garantia para
toda migration que o EF vier a gerar.

A alternativa mais restrita, registrada como evolucao, e separar **dois usuarios
por banco**: um de migration (`db_owner`, usado so no passo de migrations do CI)
e um de runtime (`db_datareader` + `db_datawriter`), cada um com connection
string propria no Key Vault. Reduz o estrago de uma aplicacao comprometida (nao altera
nem apaga o schema), ao custo de mais um usuario, um secret e uma identidade de
CI com acesso a ele por servico.

## Consequencias
### Positivas
- Cada servico so alcanca o proprio banco: credencial comprometida de um
  servico nao le nem escreve nos outros, e o administrador deixa de ser usado
  pelas aplicacoes.
- O script e idempotente e serve tambem para rotacionar senha, sem recriar nada.
- `BillingDb` segue um padrao ja conhecido (`SegurancaDb`), com custo pequeno
  gracas ao auto-pause.

### Negativas
- A mesma senha precisa existir em dois repositorios (secrets do GitHub do Banco
  e do Infra); se so um lado for rotacionado, a aplicacao deixa de conectar. Nao
  ha `terraform_remote_state` para evitar isso (ADR 0001).
- `db_owner` permite DDL: uma aplicacao comprometida ainda pode alterar ou
  apagar o schema do proprio banco (so dele).
- O passo de SQL do CI depende de instalar o go-sqlcmd pinado no runner (o
  `ubuntu-latest` nao traz `sqlcmd`), de abrir e fechar
  uma regra de firewall e de a rede do runner alcancar `svsfiap`; durante alguns
  minutos o servidor aceita conexao de um IP de runner (ainda sujeito a usuario e
  senha). Se a remocao da regra falhar, sobra uma regra `ci-runner-*` fora do
  state, que deve ser apagada manualmente.
- As connection strings ja existentes de `OficinaMecanicaDb` e `SegurancaDb` no
  Infra continuam usando o administrador ate o Infra passar a usar `app_os` e
  `app_seguranca`; isso so deve acontecer depois de este repositorio ter criado
  os usuarios.

## Alternativas consideradas
- **Continuar com o administrador nas aplicacoes**: mais simples, mas viola a
  independencia dos servicos e o menor privilegio.
- **Criar os usuarios por Terraform** (`null_resource`/`local-exec` com sqlcmd ou
  provider de terceiros para SQL Server): o provider `azurerm` nao tem recurso
  para usuario contido; as opcoes reintroduzem dependencia de binario no runner
  dentro do `apply` ou de provider nao oficial que conecta no SQL direto do
  Terraform, com a senha no state. O script versionado e mais explicito e
  revisavel.
- **Autenticacao Microsoft Entra ID (workload identity do AKS) em vez de senha**:
  elimina senha, mas exige configurar administrador Entra no servidor e
  `CREATE USER ... FROM EXTERNAL PROVIDER` executado por ele, e a Function do
  Seguranca teria de usar identidade gerenciada. Fica como evolucao possivel,
  fora do escopo desta entrega.
- **Um servidor logico por servico**: isolamento maior, mas custo e o risco de
  regiao/capacidade ja encontrado na criacao do servidor principal.
- **Dois usuarios por banco desde ja** (migration e runtime): descrito acima como
  evolucao.
