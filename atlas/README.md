# atlas/: MongoDB Atlas do OficinaMecanica.Execucao

Root Terraform **separado** do resto do Banco, com state proprio (`atlas.tfstate`, mesmo
container `tfstate` da `stfiap`). Cria o projeto `OficinaMecanica`, o cluster M0 `execucao`, o
usuario `execucao_app` (`readWrite` so no banco `execucao`), a IP access list com o IP de saida
do AKS (/32) e grava a connection string em `execucao-mongo-connection-string` no Key Vault.

**Aplicado so localmente.** O CI do Banco nao aplica nem le este root: a API de administracao
do Atlas exige IP fixo na API key e o runner do GitHub nao tem (ver `docs/adr/0004`). O CI so
roda `fmt` e `validate` aqui, sem credenciais.

## Como aplicar (da maquina de um administrador)

Precisa de `az login` com `Key Vault Administrator` no `kvfiap` e `Storage Blob Data
Contributor` no container do tfstate, e de uma API key de organizacao do Atlas (role
`Organization Project Creator`) cujo IP desta maquina esteja na access list da key.

```bash
export MONGODB_ATLAS_PUBLIC_KEY="<public key>"
export MONGODB_ATLAS_PRIVATE_KEY="<private key>"
export TF_VAR_atlas_org_id="<24 caracteres hexadecimais da organizacao>"
export TF_VAR_aks_egress_ip="<IP publico de saida do AKS>"   # ver o README da raiz

cp terraform.tfvars.example terraform.tfvars   # ajustar se preciso
terraform init
terraform plan
terraform apply
```

O cluster M0 nao e modificavel depois de criado: trocar nome ou regiao recria o cluster e apaga
os dados (por isso o `prevent_destroy`). Se o IP de saida do AKS mudar, atualize
`TF_VAR_aks_egress_ip` e aplique de novo.
