# ADR 0001: Extracao do banco em repositorio e state proprios

## Status
Aceito

## Contexto
O banco de dados (modulo `sqldb/`) originalmente vivia dentro de
`OficinaMecanica.Infra`, junto com todo o resto da infraestrutura (AKS,
ACR, Key Vault, APIM). Conforme o projeto evoluiu, ficou claro que o
ciclo de vida de um banco de dados e diferente do resto: e o recurso mais
sensivel do ecossistema (perde-lo significa perder dados de verdade, nao
so precisar reprovisionar), e normalmente muda de forma muito mais rara e
cuidadosa que o restante da infraestrutura.

## Decisao
Extrair o modulo `sqldb/` (o SQL Server logico `svsfiap` e os dois bancos
que rodam nele) pra um repositorio proprio, `OficinaMecanica.Banco`, com
**Terraform state proprio** - nao so os arquivos `.tf` movidos de lugar,
mas o proprio estado (`terraform state rm` no repositorio de origem +
`terraform import` no novo repositorio), sem destruir e recriar nenhum
recurso real no Azure durante a migracao.

De proposito, `OficinaMecanica.Banco` **nao** usa
`terraform_remote_state` pra ler o state de `OficinaMecanica.Infra` (ou
vice-versa) - cada repositorio guarda apenas variaveis simples com os
"fatos conhecidos" que precisa do outro (ex: nome do resource group, nome
do SQL Server), evitando acoplar os dois states um ao outro.

## Consequencias
### Positivas
- Uma mudanca de infraestrutura geral (ex: ajustar o APIM) nunca corre o
  risco de tocar acidentalmente no banco de dados, porque estao em states
  Terraform fisicamente separados.
- Permite (no futuro) aplicar politicas de aprovacao mais rigorosas
  especificamente para mudancas no banco, sem afetar a velocidade de
  iteracao do resto da infraestrutura.
- A ausencia de `terraform_remote_state` entre os dois repositorios evita
  que um `terraform apply` num repositorio dependa de conseguir ler o
  state remoto do outro.

### Negativas
- "Fatos conhecidos" duplicados como variaveis simples em vez de outputs
  encadeados via `terraform_remote_state` podem ficar desatualizados se um
  dos dois lados mudar e o outro nao for atualizado manualmente.
- Mais um repositorio, um state, e potencialmente uma identidade OIDC de
  CI/CD a mais pra gerenciar.

## Alternativas consideradas
- **Manter `sqldb/` dentro de `OficinaMecanica.Infra`, so em pasta
  separada**: mais simples, mas continuaria compartilhando o mesmo state -
  um erro de `terraform apply` em qualquer outro modulo desse repositorio
  continuaria colocando o banco em risco (mesmo state = mesmo raio de
  impacto de qualquer erro humano ou de plano).
- **`terraform_remote_state` entre os dois repositorios**: evitaria
  duplicar variaveis, mas acoplaria o `apply` de um repositorio a
  conseguir ler o state remoto do outro - rejeitado para manter os dois
  repositorios independentes em runtime.
