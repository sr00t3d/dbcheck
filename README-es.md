[🇺🇸 English](README.md) | [🇧🇷 Português (BR)](README-ptbr.md) | 🇪🇸 **Español**

# dbcheck — Auditor de Configuraciones y Conexiones MySQL/MariaDB Multi-CMS

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.0.0-brightgreen.svg)](https://github.com/sr00t3d/dbcheck/releases)
[![Bash](https://img.shields.io/badge/Linux-Bash%204.0%2B-4EAA25?logo=gnu-bash&logoColor=white)](dbcheck.sh)

**`dbcheck.sh`** es una CLI en Bash + Python 3 stdlib que descubre archivos de configuración de bases de datos en **10 CMS y frameworks PHP**, prueba conexiones MySQL/MariaDB en vivo de forma segura (`MYSQL_PWD`), cuenta tablas, enmascara contraseñas por defecto y exporta reportes `table`, `json` y `csv`.

> **Inspiración Histórica:** Reimplementación limpia inspirada en `DB Checker 3.2` (2013, **Rishwanth Y** / HostGator Migrations).

---

## Ejecución Directa (Linux)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sr00t3d/dbcheck/main/dbcheck.sh) -d /var/www/html --exit-code
```

---

## Autor & Licencia

Desarrollado por **Percio Castelo** ([perciocastelo.com.br](https://perciocastelo.com.br)).
Inspirado en `DB Checker 3.2` (2013, **Rishwanth Y** / HostGator Migrations).

Licenciado bajo la [Apache License 2.0](LICENSE).
