# expenses-liquibase

Migrações PostgreSQL do Expenses, com changelogs YAML e scripts SQL separados de seus rollbacks. A sprint-1 cria **33 tabelas em quatro schemas**, com PKs, FKs, unicidade, checks, índices e triggers de integridade.

As fontes, relações, premissas e responsabilidades do backend estão no [modelo físico](../docs/Modelo-Fisico-Banco-de-Dados.md). O SQL versionado é o dicionário de campos, tipos e constraints.

```text
expenses-liquibase/
├── db.changelog-master.yaml
├── config/
│   ├── liquibase.properties
│   └── liquibase.local.properties  # privado, ignorado pelo Git
├── changelogs/
│   └── sprint-1/
│       ├── changelog.yaml
│       ├── sql/
│       └── rollback/
└── tests/
    ├── validate_schema.py
    └── schema_checks.sql
```

O master referencia o changelog da sprint-1, com os seguintes changeSets:

| ChangeSet | Conteúdo |
| --- | --- |
| `sprint-1-001` | Schemas `identity`, `household`, `finance` e `income`. |
| `sprint-1-002` | Usuários, tentativas/bloqueios de login, reconciliação, idempotência e auditoria de identidade. |
| `sprint-1-003` | Casas, membros, convites, idempotência e auditoria da casa. |
| `sprint-1-004` | Períodos, categorias, pagamentos, despesas, participantes, salários, benefícios e prioridades. |
| `sprint-1-005` | Fontes e lançamentos de renda, idempotência e auditoria de renda. |
| `sprint-1-006` | Versões de fechamento e snapshots de rateio. |
| `sprint-1-007` | Importações, mapeamentos de origem, exportações, revisões, idempotência e auditoria financeira. |
| `sprint-1-008` | Triggers de integridade e proteção de histórico. |

Cada changeSet é transacional. O arquivo de funções usa `splitStatements: false` para preservar os blocos PL/pgSQL. Os rollbacks removem os objetos na ordem inversa das dependências, sem `CASCADE`. Depois de uma aplicação compartilhada, evolua o modelo com novos changeSets; preserve os existentes e seus checksums.

## Configuração e aplicação

Validado com **PostgreSQL 17.11**, **Liquibase 4.33.0** e Java disponível no ambiente. Não requer extensões PostgreSQL. Execute os comandos a partir deste diretório.

`config/liquibase.properties` aponta para `jdbc:postgresql://127.0.0.1:5432/expenses`, usuário `admin`, driver PostgreSQL e schema padrão `public`. A URL pode ser substituída por `LIQUIBASE_COMMAND_URL`. O usuário de migração precisa criar schemas, tabelas, índices, funções e triggers.

Neste ambiente, `config/liquibase.local.properties` já contém a conexão completa, com a senha obtida do `.env` da raiz. Esse arquivo tem permissão `0600` e é ignorado pelo Git. Para conferir a conexão e as migrações pendentes:

```bash
liquibase --defaults-file=config/liquibase.local.properties status --verbose
```

Para aplicar as migrações no banco local:

```bash
liquibase --defaults-file=config/liquibase.local.properties update
```

Se a senha do PostgreSQL mudar, atualize também o arquivo local. Em outros ambientes, use `LIQUIBASE_COMMAND_USERNAME` e `LIQUIBASE_COMMAND_PASSWORD` com o arquivo de configuração sem credenciais.

Para utilizar as credenciais locais já mantidas no `.env` da raiz, em um subshell:

```bash
(
  . ../.env
  export LIQUIBASE_COMMAND_USERNAME="$POSTGRES_USER"
  export LIQUIBASE_COMMAND_PASSWORD="$POSTGRES_PASSWORD"
  liquibase --defaults-file=config/liquibase.properties validate
  liquibase --defaults-file=config/liquibase.properties update-sql
  liquibase --defaults-file=config/liquibase.properties update
)
```

`update-sql` mostra o SQL; `update` aplica as migrações no banco configurado. Liquibase mantém suas tabelas de controle em `public`. EF Core/Npgsql será usado pelo backend para acesso aos dados; a evolução deste schema pertence ao Liquibase.

## Validação isolada

Com Python 3, Liquibase e o container `expenses-postgres` em execução no contexto Docker Desktop `desktop-linux`:

```bash
python3 tests/validate_schema.py
```

O teste usa as variáveis Liquibase ou as credenciais do `.env` da raiz. Cria um banco com nome aleatório `expenses_sprint1_check_*`, executa `validate`, `update`, reaplicação sem mudanças, testes SQL, rollback dos oito changeSets e nova aplicação. Remove somente esse banco temporário ao terminar. O banco `expenses` não recebe as migrações durante esse teste.

Os cenários verificam chaves entre casas e competências, unicidade, valores inválidos, participantes, administrador obrigatório, reconfirmação de pagamento, idempotência, período fechado, preservação dos fechamentos e cobertura de índices para todas as FKs. Usam dados sintéticos; não implementam nem validam o algoritmo de rateio, a autorização HTTP ou o importador legado.

## Rollback

No banco configurado, imediatamente após esta sprint e sem changeSets posteriores:

```bash
liquibase --defaults-file=config/liquibase.properties rollback-count --count=8
```

Esse comando remove as tabelas da sprint **e seus dados**. Foi validado no banco temporário. Em bases com dados a preservar, a evolução normal deve usar novas migrações.
