# RFC 0001: Escolha do banco de dados (Azure SQL Database serverless)

## Status
Aceito

## Resumo
Tanto `OficinaMecanica` (monolito) quanto `OficinaMecanica.Seguranca`
(autenticacao) persistem dados num unico **SQL Server logico** do Azure
(`svsfiap`), cada um com seu proprio banco (`OficinaMecanicaDb` e
`SegurancaDb`), rodando no tier **serverless**.

## Motivacao
O dominio (clientes, veiculos, ordens de servico, pecas, servicos,
usuarios/credenciais) e fundamentalmente relacional, com integridade
referencial importante entre entidades (uma ordem de servico referencia
cliente, veiculo, itens de peca/servico). A stack de aplicacao e .NET com
Entity Framework Core, que tem suporte de primeira classe para SQL Server
via o provider `Microsoft.EntityFrameworkCore.SqlServer`.

Custo tambem pesou: o projeto roda numa assinatura Azure for Students, sem
trafego constante - pagar
por um banco sempre ligado (tier provisionado, DTU ou vCore fixo) seria
desperdicio na maior parte do tempo.

## Proposta
Azure SQL Database, tier **serverless** (auto-pausa quando ocioso, cobra
por segundo de computo realmente usado) - nao Cosmos DB (NoSQL, sem o
encaixe natural com um dominio relacional forte) nem uma VM com SQL Server
instalado manualmente (sem gerenciamento automatico de patch/backup).

## Alternativas consideradas
- **Azure Database for PostgreSQL / MySQL Flexible Server**: tambem
  relacionais e com tier serverless/burstable, mas o provider EF Core pra
  SQL Server e o de primeira parte da Microsoft - menos fricao de
  compatibilidade dado que o resto da stack ja e 100% .NET.
- **Cosmos DB**: tier gratuito generoso, mas modelo de dados
  documento/NoSQL nao se encaixa bem num dominio com relacionamentos
  fortes (ordem de servico -> cliente -> veiculo -> itens) sem reformular
  o desenho do dominio em torno das limitacoes de um banco nao-relacional.
- **SQL Server em VM**: descartado cedo - exige gerenciar patch, backup e
  disponibilidade manualmente, o oposto do que se busca ao usar servicos
  gerenciados (PaaS) no resto do ecossistema.

## Consequencias conhecidas
O tier serverless tem um efeito colateral real: apos um periodo ocioso, o
banco "pausa" e a primeira conexao apos a pausa demora mais que o normal
pra ser estabelecida (cold start), podendo causar falhas transitorias de
conexao se a aplicacao nao tiver alguma forma de retry. Isso foi
observado na pratica e exigiu adicionar resiliencia a falha transitoria no
lado do `OficinaMecanica` (ver historico de commits do repositorio
`OficinaMecanica`).

## Decisao
Azure SQL Database serverless, um SQL Server logico compartilhado entre
os dois bancos do ecossistema (`OficinaMecanicaDb`, `SegurancaDb`) -
compartilhar o servidor (nao o banco) reduz custo sem misturar os dados
dos dois servicos.
