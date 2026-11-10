-- Cria (ou ressincroniza a senha de) um usuario SQL contido, dedicado ao banco
-- em que o sqlcmd esta conectado (-d). Roda uma vez por banco no job apply do
-- CI, depois do terraform apply, conectado como administrador do servidor.
--
-- Variaveis sqlcmd (este arquivo nunca tem senha literal):
--   NomeUsuario   app_os, app_seguranca ou app_billing; vai por -v
--   SenhaUsuario  vai por variavel de ambiente de mesmo nome, definida so no
--                 processo do sqlcmd (o go-sqlcmd resolve a variavel do script
--                 a partir do ambiente), para a senha nao aparecer na linha
--                 de comando; nao pode ter aspas simples
--
-- Optei por usuario contido (sem login no master) porque a credencial so
-- existe dentro deste banco: nao ha como reaproveita-la em outro banco do
-- servidor nem no master. Por isso a connection string precisa trazer o
-- banco (Initial Catalog), senao o login falha.
--
-- db_owner, e so neste banco, e o minimo pratico: o mesmo usuario roda o
-- "dotnet ef database update" no CI de cada servico (CREATE/ALTER/DROP de
-- tabela, indice e FK, sp_rename e a tabela __EFMigrationsHistory, alem das
-- tabelas de saga/outbox do MassTransit) e o runtime da aplicacao. Os papeis
-- db_ddladmin + db_datareader + db_datawriter cobrem a maior parte, mas nao
-- ha garantia de que cubram toda migration que o EF gerar. A alternativa
-- mais restrita e separar dois usuarios por banco: um de
-- migration (db_owner, usado so no passo de migrations do CI) e um de
-- runtime (db_datareader + db_datawriter), cada um com connection string
-- propria no Key Vault. Fica como evolucao, ver ADR 0003.
--
-- Idempotente: se o usuario ja existe, so sincroniza a senha (rotacao pelo
-- secret do GitHub); se ja e db_owner, nao repete a associacao.

SET NOCOUNT ON;
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$(NomeUsuario)')
BEGIN
    ALTER USER [$(NomeUsuario)] WITH PASSWORD = N'$(SenhaUsuario)';
    PRINT N'Usuario $(NomeUsuario): senha sincronizada.';
END
ELSE
BEGIN
    CREATE USER [$(NomeUsuario)] WITH PASSWORD = N'$(SenhaUsuario)', DEFAULT_SCHEMA = [dbo];
    PRINT N'Usuario $(NomeUsuario): criado.';
END
GO

IF ISNULL(IS_ROLEMEMBER(N'db_owner', N'$(NomeUsuario)'), 0) = 0
BEGIN
    ALTER ROLE db_owner ADD MEMBER [$(NomeUsuario)];
    PRINT N'Usuario $(NomeUsuario): adicionado a db_owner.';
END
GO
