[🇺🇸 English](README.md) | 🇧🇷 **Português (BR)** | [🇪🇸 Español](README-es.md)

# dbcheck — Auditor de Configurações e Conexões MySQL/MariaDB Multi-CMS

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.0.0-brightgreen.svg)](https://github.com/sr00t3d/dbcheck/releases)
[![Bash](https://img.shields.io/badge/Linux-Bash%204.0%2B-4EAA25?logo=gnu-bash&logoColor=white)](dbcheck.sh)

O **`dbcheck.sh`** é uma CLI em Bash + Python 3 stdlib que descobre automaticamente arquivos de configuração de banco de dados em **10 CMS e frameworks PHP populares**, testa a conexão MySQL/MariaDB ao vivo com segurança (via `MYSQL_PWD`, sem expor senha na lista de processos), conta as tabelas de cada banco, mascara senhas por padrão e exporta relatórios em `table`, `json` e `csv` — ideal para validação pós-migração em servidores cPanel/WHM, Plesk, DirectAdmin ou Linux avulso.

> **Inspiração Histórica:** Reimplementação limpa inspirada no `DB Checker 3.2` (2013, **Rishwanth Y** / HostGator Migrations). Remove a dependência morta de `xfermodules.pm` / `dbconnect` e adiciona suporte a Laravel `.env`, Magento 2, PrestaShop 1.7/8 e Drupal 8–11.

---

## Execução Direta (Linux)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sr00t3d/dbcheck/main/dbcheck.sh) -d /var/www/html --exit-code
```

---

## Instalação e Uso

```bash
git clone https://github.com/sr00t3d/dbcheck.git
cd dbcheck
chmod +x dbcheck.sh

./dbcheck.sh -d /home/alice/public_html
./dbcheck.sh -u alice --bad --exit-code
./dbcheck.sh -d /home/alice/public_html --remotehost 10.0.0.25 -o json
./dbcheck.sh -d /home/alice/public_html --dump-file /root/alice-dbs.txt
```

---

## Autor & Licença

Desenvolvido por **Percio Castelo** ([perciocastelo.com.br](https://perciocastelo.com.br)).
Inspirado no `DB Checker 3.2` (2013, **Rishwanth Y** / HostGator Migrations).

Licenciado sob a [Apache License 2.0](LICENSE).
