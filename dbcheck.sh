#!/usr/bin/env bash
# ==============================================================================
#  dbcheck.sh — Multi-CMS Database Config Discovery & Live Connection Auditor
# ==============================================================================
#  Author  : Percio Castelo <percio@perciocastelo.com.br>
#  Website : https://perciocastelo.com.br
#  Project : https://perciocastelo.com.br/projetos/en/dbcheck.html
#  Repo    : https://github.com/sr00t3d/dbcheck
#  License : Apache-2.0
#  Version : 2.0.0
#  Notes   : Clean-room Bash + Python 3 stdlib reimplementation inspired by
#            `DB Checker 3.2` (2013, Rishwanth Y / HostGator Migrations).
#            Eliminates legacy `xfermodules.pm`/`dbconnect` dependencies, adds
#            modern CMS/framework parsers (WordPress, Laravel/.env, WHMCS,
#            Joomla, PrestaShop, Magento 2, Drupal, OpenCart, Moodle), tests
#            live MySQL/MariaDB connectivity safely via MYSQL_PWD, masks
#            passwords by default, and exports table/json/csv reports.
# ==============================================================================

set -uo pipefail
export LC_ALL=C

readonly SCRIPT_NAME="dbcheck.sh"
readonly SCRIPT_VERSION="2.0.0"

# Defaults
TARGET_DIR=""
CPANEL_USER=""
USERLIST_FILE=""
REMOTE_HOST=""
BAD_ONLY=0
SHOW_PASSWORDS=0
DUMP_FILE=""
TIMEOUT_SEC=5
MAX_DEPTH=5
EXIT_CODE_MODE=0
FORMAT="table"
QUIET=0
NO_COLOR=0
TIMESTAMP_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

show_help() {
  cat <<'USAGE'
dbcheck.sh v2.0.0 — Multi-CMS Database Config Discovery & Live Connection Auditor

Usage:
  dbcheck.sh [options] [directory]

Supported CMS / Frameworks:
  WordPress (wp-config.php), Laravel/Symfony/Node (.env), WHMCS (configuration.php),
  Joomla (configuration.php), PrestaShop 1.6-8 (parameters.php / settings.inc.php),
  Magento 2 (app/etc/env.php), Drupal 8-11 (settings.php), OpenCart & Moodle (config.php)

Options:
  -d, --dir <path>           Directory to scan (default: current working directory)
  -u, --user <username>      cPanel mode: scan /home/<username>
  --userlist <file>          cPanel mode: scan all users listed in file (one per line)
  --remotehost <ip|host>     Fallback/override MySQL host for remote migration tests
  --bad                      Display only FAILED database connections
  --show-passwords           Display plaintext DB passwords (default: masked as ********)
  -f, --dump-file <path>     Save discovered credentials to a chmod 600 file
  --timeout <sec>            MySQL connection timeout in seconds (default: 5)
  --max-depth <n>            Max directory recursion depth (default: 5)
  --exit-code                Exit with code 2 if any discovered DB config fails to connect
  -o, --output <fmt>         Output format: table (default), json, csv
  -q, --quiet                Suppress banner header
  --no-color                 Disable ANSI colors
  -V, --version              Show version and exit
  -h, --help                 Show this help and exit

Examples:
  dbcheck.sh -d /home/alice/public_html
  dbcheck.sh -u alice --bad --exit-code
  dbcheck.sh -d /var/www --remotehost 10.0.0.25 -o json
USAGE
}

main() {
  command -v python3 >/dev/null 2>&1 || { printf '[ERR] python3 is required.\n' >&2; exit 1; }
  local mysql_bin=""
  if command -v mysql >/dev/null 2>&1; then
    mysql_bin="$(command -v mysql)"
  elif command -v mariadb >/dev/null 2>&1; then
    mysql_bin="$(command -v mariadb)"
  else
    printf '[ERR] Neither mysql nor mariadb client binary was found.\n' >&2
    exit 1
  fi

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -h|--help)        show_help; exit 0 ;;
      -V|--version)     printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"; exit 0 ;;
      -d|--dir|--directory) TARGET_DIR="${2:-}"; shift 2 ;;
      -u|--user)        CPANEL_USER="${2:-}"; shift 2 ;;
      --userlist)       USERLIST_FILE="${2:-}"; shift 2 ;;
      --remotehost)     REMOTE_HOST="${2:-}"; shift 2 ;;
      --bad)            BAD_ONLY=1; shift ;;
      --show-passwords) SHOW_PASSWORDS=1; shift ;;
      -f|--dump-file|--dumptofile) DUMP_FILE="${2:-}"; shift 2 ;;
      --timeout)        TIMEOUT_SEC="${2:-5}"; shift 2 ;;
      --max-depth)      MAX_DEPTH="${2:-5}"; shift 2 ;;
      --exit-code)      EXIT_CODE_MODE=1; shift ;;
      -o|--output)      FORMAT="${2:-table}"; shift 2 ;;
      --output=*)       FORMAT="${1#*=}"; shift ;;
      -q|--quiet)       QUIET=1; shift ;;
      --no-color)       NO_COLOR=1; shift ;;
      -*)               printf '[ERR] Unknown option: %s (use -h for help)\n' "$1" >&2; exit 1 ;;
      *)
        if [[ -z "$TARGET_DIR" ]]; then
          TARGET_DIR="$1"; shift
        else
          printf '[ERR] Unexpected argument: %s\n' "$1" >&2; exit 1
        fi ;;
    esac
  done

  case "$FORMAT" in
    table|json|csv) ;;
    *) printf '[ERR] Invalid output format: %s (expected table, json, or csv)\n' "$FORMAT" >&2; exit 1 ;;
  esac

  local use_color=0
  if [[ "$NO_COLOR" -eq 0 && -t 1 && -z "${NO_COLOR:-}" && "$FORMAT" == "table" ]]; then
    use_color=1
  fi

  local py_script
  py_script="$(cat <<'PYEOF'
import csv
import io
import json
import os
import pwd
import re
import stat
import subprocess
import sys

(
    script_name,
    script_version,
    timestamp_utc,
    mysql_bin,
    target_dir,
    cpanel_user,
    userlist_file,
    remote_host,
    bad_only_s,
    show_passwords_s,
    dump_file,
    timeout_s,
    max_depth_s,
    exit_code_mode_s,
    fmt,
    quiet_s,
    use_color_s,
) = sys.argv[1:18]

bad_only = bad_only_s == "1"
show_passwords = show_passwords_s == "1"
timeout_sec = int(timeout_s)
max_depth = int(max_depth_s)
exit_code_mode = exit_code_mode_s == "1"
quiet = quiet_s == "1"
use_color = use_color_s == "1"

C_CYN = "\033[0;36m" if use_color else ""
C_GRN = "\033[0;32m" if use_color else ""
C_RED = "\033[0;31m" if use_color else ""
C_YEL = "\033[0;33m" if use_color else ""
C_BLD = "\033[1m" if use_color else ""
C_RST = "\033[0m" if use_color else ""

OMIT_DIRS = {".git", "node_modules", "vendor", "cache", "tmp", "mail", ".cpanel", ".security", "virtfs"}
TARGET_FILENAMES = {"wp-config.php", ".env", "configuration.php", "parameters.php", "settings.inc.php", "env.php", "settings.php", "config.php"}

def resolve_homedir(user):
    try:
        return pwd.getpwnam(user).pw_dir
    except KeyError:
        p = os.path.join("/home", user)
        return p if os.path.isdir(p) else ""

scan_roots = []
if target_dir:
    if not os.path.isdir(target_dir):
        sys.stderr.write("[ERR] Directory not found: %s\n" % target_dir)
        sys.exit(1)
    scan_roots.append(os.path.abspath(target_dir))
if cpanel_user:
    hd = resolve_homedir(cpanel_user)
    if not hd:
        sys.stderr.write("[ERR] Could not resolve home directory for user: %s\n" % cpanel_user)
        sys.exit(1)
    scan_roots.append(hd)
if userlist_file:
    if not os.path.isfile(userlist_file):
        sys.stderr.write("[ERR] Userlist file not found: %s\n" % userlist_file)
        sys.exit(1)
    with open(userlist_file, "r", encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            u = line.split("#", 1)[0].strip()
            if u:
                hd = resolve_homedir(u)
                if hd:
                    scan_roots.append(hd)
if not scan_roots:
    scan_roots.append(os.getcwd())

def parse_config(fpath):
    fn = os.path.basename(fpath)
    try:
        with open(fpath, "r", encoding="utf-8", errors="ignore") as fh:
            txt = fh.read(262144)
    except OSError:
        return None

    # 1. WordPress
    if fn == "wp-config.php":
        def wp_def(k):
            m = re.search(r"define\s*\(\s*['\"]%s['\"]\s*,\s*['\"]([^'\"]*)['\"]\s*\)" % k, txt)
            return m.group(1) if m else ""
        db = wp_def("DB_NAME")
        if db:
            return {"app": "WordPress", "db": db, "user": wp_def("DB_USER"), "pass": wp_def("DB_PASSWORD"), "host": wp_def("DB_HOST") or "localhost"}

    # 2. Laravel / .env
    if fn == ".env":
        kv = {}
        for line in txt.splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            k = k.strip()
            v = v.strip().strip('"').strip("'")
            kv[k] = v
        if kv.get("DB_DATABASE") and kv.get("DB_USERNAME"):
            conn = kv.get("DB_CONNECTION", "mysql").lower()
            if conn in ("mysql", "mariadb", ""):
                host = kv.get("DB_HOST", "127.0.0.1")
                port = kv.get("DB_PORT", "")
                if port and port != "3306":
                    host = "%s:%s" % (host, port)
                return {"app": "Laravel/.env", "db": kv["DB_DATABASE"], "user": kv["DB_USERNAME"], "pass": kv.get("DB_PASSWORD", ""), "host": host}

    # 3. WHMCS or Joomla (configuration.php)
    if fn == "configuration.php":
        m_whmcs = re.search(r"\$db_name\s*=\s*['\"]([^'\"]+)['\"]", txt)
        if m_whmcs:
            def php_var(v):
                m = re.search(r"\$%s\s*=\s*['\"]([^'\"]*)['\"]" % v, txt)
                return m.group(1) if m else ""
            return {"app": "WHMCS", "db": m_whmcs.group(1), "user": php_var("db_username"), "pass": php_var("db_password"), "host": php_var("db_host") or "localhost"}
        if "JConfig" in txt:
            def j_var(v):
                m = re.search(r"public\s+\$%s\s*=\s*['\"]([^'\"]*)['\"]" % v, txt)
                return m.group(1) if m else ""
            db = j_var("db")
            if db:
                return {"app": "Joomla", "db": db, "user": j_var("user"), "pass": j_var("password"), "host": j_var("host") or "localhost"}

    # 4. PrestaShop 1.7 / 8 (app/config/parameters.php)
    if fn == "parameters.php" and "database_name" in txt:
        def ps_val(k):
            m = re.search(r"['\"]%s['\"]\s*=>\s*['\"]([^'\"]*)['\"]" % k, txt)
            return m.group(1) if m else ""
        db = ps_val("database_name")
        if db:
            return {"app": "PrestaShop", "db": db, "user": ps_val("database_user"), "pass": ps_val("database_password"), "host": ps_val("database_host") or "localhost"}

    # 5. PrestaShop 1.6 (settings.inc.php)
    if fn == "settings.inc.php" and "_DB_NAME_" in txt:
        def ps6(k):
            m = re.search(r"define\s*\(\s*['\"]%s['\"]\s*,\s*['\"]([^'\"]*)['\"]\s*\)" % k, txt)
            return m.group(1) if m else ""
        db = ps6("_DB_NAME_")
        if db:
            return {"app": "PrestaShop-1.6", "db": db, "user": ps6("_DB_USER_"), "pass": ps6("_DB_PASSWD_"), "host": ps6("_DB_SERVER_") or "localhost"}

    # 6. Magento 2 (app/etc/env.php)
    if fn == "env.php" and "dbname" in txt and "connection" in txt:
        def mag_val(k):
            m = re.search(r"['\"]%s['\"]\s*=>\s*['\"]([^'\"]*)['\"]" % k, txt)
            return m.group(1) if m else ""
        db = mag_val("dbname")
        if db:
            return {"app": "Magento2", "db": db, "user": mag_val("username"), "pass": mag_val("password"), "host": mag_val("host") or "localhost"}

    # 7. Drupal 8-11 (settings.php)
    if fn == "settings.php" and "$databases" in txt and "database" in txt:
        def dr_val(k):
            m = re.search(r"['\"]%s['\"]\s*=>\s*['\"]([^'\"]*)['\"]" % k, txt)
            return m.group(1) if m else ""
        db = dr_val("database")
        if db and dr_val("username"):
            return {"app": "Drupal", "db": db, "user": dr_val("username"), "pass": dr_val("password"), "host": dr_val("host") or "localhost"}

    # 8. OpenCart or Moodle (config.php)
    if fn == "config.php":
        if "DB_DATABASE" in txt and "DB_USERNAME" in txt:
            def oc(k):
                m = re.search(r"define\s*\(\s*['\"]%s['\"]\s*,\s*['\"]([^'\"]*)['\"]\s*\)" % k, txt)
                return m.group(1) if m else ""
            db = oc("DB_DATABASE")
            if db:
                return {"app": "OpenCart", "db": db, "user": oc("DB_USERNAME"), "pass": oc("DB_PASSWORD"), "host": oc("DB_HOSTNAME") or "localhost"}
        if "$CFG->dbname" in txt:
            def md(k):
                m = re.search(r"\$CFG->%s\s*=\s*['\"]([^'\"]*)['\"]" % k, txt)
                return m.group(1) if m else ""
            db = md("dbname")
            if db:
                return {"app": "Moodle", "db": db, "user": md("dbuser"), "pass": md("dbpass"), "host": md("dbhost") or "localhost"}

    return None

def test_mysql(host, user, password, db):
    h = host
    port = "3306"
    if ":" in h and not h.startswith("/"):
        h, port = h.rsplit(":", 1)
    env = os.environ.copy()
    env["MYSQL_PWD"] = password
    cmd = [
        mysql_bin,
        "--batch",
        "--skip-column-names",
        "--connect-timeout=%d" % timeout_sec,
        "-h", h,
        "-P", port,
        "-u", user,
        db,
        "-e", "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE();",
    ]
    try:
        proc = subprocess.run(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout_sec + 3)
        if proc.returncode == 0:
            out = proc.stdout.decode("utf-8", errors="ignore").strip()
            tables = int(out) if out.isdigit() else 0
            return True, tables, ""
        err = proc.stderr.decode("utf-8", errors="ignore").strip().splitlines()
        msg = err[-1] if err else "connection failed"
        return False, 0, msg[:140]
    except Exception as e:
        return False, 0, str(e)[:140]

def iter_configs(root):
    base_depth = root.rstrip(os.sep).count(os.sep)
    for cur_root, dirs, files in os.walk(root, followlinks=False):
        cur_depth = cur_root.rstrip(os.sep).count(os.sep) - base_depth
        dirs[:] = [
            d for d in dirs
            if d not in OMIT_DIRS
            and not os.path.islink(os.path.join(cur_root, d))
            and (max_depth == 0 or cur_depth < max_depth)
        ]
        for fn in files:
            if fn not in TARGET_FILENAMES:
                continue
            full = os.path.join(cur_root, fn)
            try:
                st = os.lstat(full)
                if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode):
                    continue
            except OSError:
                continue
            yield full

results = []
good_count = 0
bad_count = 0

for root in scan_roots:
    for cfg_path in iter_configs(root):
        parsed = parse_config(cfg_path)
        if not parsed:
            continue
        used_host = parsed["host"]
        ok, tables, err = test_mysql(used_host, parsed["user"], parsed["pass"], parsed["db"])
        if not ok and remote_host and used_host != remote_host:
            ok2, tables2, err2 = test_mysql(remote_host, parsed["user"], parsed["pass"], parsed["db"])
            if ok2:
                ok, tables, err, used_host = ok2, tables2, err2, remote_host
        if ok:
            good_count += 1
        else:
            bad_count += 1
        results.append({
            "app": parsed["app"],
            "file": cfg_path,
            "host": used_host,
            "db": parsed["db"],
            "user": parsed["user"],
            "password": parsed["pass"] if show_passwords else "********",
            "raw_password": parsed["pass"],
            "status": "OK" if ok else "FAIL",
            "tables": tables,
            "error": err,
        })

if dump_file and results:
    with open(dump_file, "w", encoding="utf-8") as df:
        for r in results:
            df.write("%s %s %s %s %s %s\n" % (r["db"], r["user"], r["raw_password"], r["host"], r["app"], r["status"]))
    try:
        os.chmod(dump_file, 0o600)
    except OSError:
        pass

public_results = []
for r in results:
    if bad_only and r["status"] == "OK":
        continue
    item = dict(r)
    item.pop("raw_password", None)
    public_results.append(item)

report = {
    "tool": script_name,
    "version": script_version,
    "timestamp": timestamp_utc,
    "roots": scan_roots,
    "total_configs": len(results),
    "good": good_count,
    "bad": bad_count,
    "results": public_results,
}

if fmt == "json":
    print(json.dumps(report, indent=2))
elif fmt == "csv":
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(["app", "status", "tables", "host", "db", "user", "password", "file", "error"])
    for r in public_results:
        w.writerow([r["app"], r["status"], r["tables"], r["host"], r["db"], r["user"], r["password"], r["file"], r["error"]])
    sys.stdout.write(buf.getvalue())
else:
    if not quiet:
        print("%s%s%s" % (C_CYN, "=" * 86, C_RST))
        print(" %s%s v%s%s | Multi-CMS Database Connection Auditor | %s" % (
            C_BLD, script_name, script_version, C_RST, timestamp_utc
        ))
        print("%s%s%s" % (C_CYN, "=" * 86, C_RST))
    if not public_results:
        print("%s[OK]%s No matching database configs to display (scanned: %d total, %d good, %d bad)." % (
            C_GRN, C_RST, len(results), good_count, bad_count
        ))
    else:
        for r in public_results:
            col = C_GRN if r["status"] == "OK" else C_RED
            tag = "[OK]  " if r["status"] == "OK" else "[FAIL]"
            extra = "tables=%d" % r["tables"] if r["status"] == "OK" else r["error"]
            print("%s%s%s %-14s %-18s user=%-14s host=%-12s %s" % (
                col, tag, C_RST, r["app"], r["db"], r["user"], r["host"], extra
            ))
            print("       file: %s%s" % (r["file"], (" | pass: %s" % r["password"]) if show_passwords else ""))
    if not quiet:
        print("")
        print("Summary: %d config(s) | %d OK | %d FAIL" % (len(results), good_count, bad_count))
        if dump_file and results:
            print("Dumped : %s (chmod 600)" % dump_file)

if exit_code_mode and bad_count > 0:
    sys.exit(2)
sys.exit(0)
PYEOF
)"

  python3 -c "$py_script" "$SCRIPT_NAME" "$SCRIPT_VERSION" "$TIMESTAMP_UTC" \
    "$mysql_bin" "$TARGET_DIR" "$CPANEL_USER" "$USERLIST_FILE" "$REMOTE_HOST" \
    "$BAD_ONLY" "$SHOW_PASSWORDS" "$DUMP_FILE" "$TIMEOUT_SEC" "$MAX_DEPTH" \
    "$EXIT_CODE_MODE" "$FORMAT" "$QUIET" "$use_color"
}

main "$@"
