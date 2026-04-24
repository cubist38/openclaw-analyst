#!/bin/bash
set -euo pipefail

readonly_user="${MYSQL_READONLY_USER:-brewlytics_ro}"
readonly_password="${MYSQL_READONLY_PASSWORD:-brewlytics_readonly_change_me}"
database="${MYSQL_DATABASE:-brewlytics}"

mysql --protocol=socket -uroot -p"${MYSQL_ROOT_PASSWORD}" <<SQL
CREATE USER IF NOT EXISTS '${readonly_user}'@'%' IDENTIFIED BY '${readonly_password}';
ALTER USER '${readonly_user}'@'%' IDENTIFIED BY '${readonly_password}';
REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${readonly_user}'@'%';
GRANT SELECT ON \`${database}\`.* TO '${readonly_user}'@'%';
FLUSH PRIVILEGES;
SQL
