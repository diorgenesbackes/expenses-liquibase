"""Validate the complete Liquibase lifecycle in an isolated, disposable database."""

import os
from pathlib import Path
import shlex
import subprocess
import uuid


PROJECT = Path(__file__).resolve().parents[1]
DB_NAME = 'expenses_sprint1_check_' + uuid.uuid4().hex[:12]
DOCKER = ['docker', '--context', 'desktop-linux', 'exec', '-i', 'expenses-postgres']


def execute(args, **kwargs):
    result = subprocess.run(args, cwd=PROJECT, text=True, capture_output=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f"Command failed: {args[0]}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def main():
    config = {}
    env_file = PROJECT.parent / '.env'
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            if line.strip() and not line.lstrip().startswith('#'):
                key, value = line.split('=', 1)
                config[key.strip()] = shlex.split(value, comments=False)[0]
    username = os.environ.get('LIQUIBASE_COMMAND_USERNAME', config.get('POSTGRES_USER', 'admin'))
    password = os.environ.get('LIQUIBASE_COMMAND_PASSWORD', config.get('POSTGRES_PASSWORD'))
    if not password:
        raise RuntimeError('Configure LIQUIBASE_COMMAND_PASSWORD or POSTGRES_PASSWORD in .env.')
    env = os.environ.copy()
    env.update(LIQUIBASE_COMMAND_USERNAME=username, LIQUIBASE_COMMAND_PASSWORD=password,
               LIQUIBASE_COMMAND_URL=f'jdbc:postgresql://127.0.0.1:5432/{DB_NAME}')
    psql = DOCKER + ['psql', '-X', '-U', username, '-d', DB_NAME, '-v', 'ON_ERROR_STOP=1', '-At']

    def query(sql):
        return execute(psql + ['-c', sql]).strip()

    def liquibase(*args):
        execute(['liquibase', '--defaults-file=config/liquibase.properties', *args], env=env)

    created = False
    try:
        execute(DOCKER + ['createdb', '-U', username, DB_NAME])
        created = True
        print(f'Isolated validation database: {DB_NAME}', flush=True)
        liquibase('validate')
        liquibase('update')
        assert query('SELECT count(*) FROM public.databasechangelog') == '8'
        print('PASS: validate and first update (8 changeSets).', flush=True)
        liquibase('update')
        assert query('SELECT count(*) FROM public.databasechangelog') == '8'
        print('PASS: repeated update does not reapply changeSets.', flush=True)
        execute(psql, input=(PROJECT / 'tests/schema_checks.sql').read_text())
        print('PASS: relational integrity, lifecycle and catalog checks.', flush=True)
        liquibase('rollback-count', '--count=8')
        assert query("SELECT count(*) FROM pg_namespace WHERE nspname IN ('identity','household','finance','income')") == '0'
        assert query('SELECT count(*) FROM public.databasechangelog') == '0'
        print('PASS: complete rollback removes the four application schemas.', flush=True)
        liquibase('update')
        assert query("SELECT count(*) FROM pg_tables WHERE schemaname IN ('identity','household','finance','income')") == '33'
        assert query('SELECT count(*) FROM public.databasechangelog') == '8'
        print('PASS: update after rollback recreates all 33 tables.', flush=True)
    finally:
        if created:
            # Only this script's uniquely named database is eligible for cleanup.
            assert DB_NAME.startswith('expenses_sprint1_check_') and DB_NAME != 'expenses'
            execute(DOCKER + ['dropdb', '-U', username, DB_NAME])
            print('Temporary validation database removed; expenses was not modified.', flush=True)


if __name__ == '__main__':
    main()
