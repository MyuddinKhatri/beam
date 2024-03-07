#!/bin/bash

export PIP_ROOT_USER_ACTION=ignore

set -e

# Check for merge conflicts before proceeding
python -m compileall -f "${GITHUB_WORKSPACE}"
if grep -lr --exclude-dir=node_modules "^<<<<<<< " "${GITHUB_WORKSPACE}"
    then echo "Found merge conflicts"
    exit 1
fi

cd ~ || exit

# sudo apt update -y && sudo apt install redis-server -y 

pip install --upgrade pip
pip install frappe-bench

mysql --host 127.0.0.1 --port 3306 -u root -e "SET GLOBAL character_set_server = 'utf8mb4'"
mysql --host 127.0.0.1 --port 3306 -u root -e "SET GLOBAL collation_server = 'utf8mb4_unicode_ci'"

mysql --host 127.0.0.1 --port 3306 -u root -e "CREATE OR REPLACE DATABASE test_site"
mysql --host 127.0.0.1 --port 3306 -u root -e "CREATE OR REPLACE USER 'test_site'@'localhost' IDENTIFIED BY 'test_site'"
mysql --host 127.0.0.1 --port 3306 -u root -e "GRANT ALL PRIVILEGES ON \`test_site\`.* TO 'test_site'@'localhost'"

mysql --host 127.0.0.1 --port 3306 -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'root'"  # match site_cofig
mysql --host 127.0.0.1 --port 3306 -u root -e "FLUSH PRIVILEGES"

echo "------ CI VARIABLES ------"
echo "GITHUB_EVENT_NAME:"
echo "${GITHUB_EVENT_NAME}"  # push, pull_request
echo "GITHUB_BASE_REF:"  # only works when event is pull request
echo "${GITHUB_BASE_REF}"  # blank for push, version-14 for pull_request
echo "GITHUB_REF_NAME (for push/tag, format for PR is pr#/merge):"
echo "${GITHUB_REF_NAME}"  # version-15 for push, pr#/merge for pull_request
echo "--------------------------"

if [ "${GITHUB_EVENT_NAME}" = 'pull_request' ]; then
    echo "GITHUB_EVENT_NAME IS pull_request"
    BRANCH_NAME="${GITHUB_BASE_REF}"
else
    echo "GITHUB_EVENT_NAME IS push"
    BRANCH_NAME="${GITHUB_REF_NAME}"
fi
echo "BRANCH_NAME IS: ${BRANCH_NAME}"

git clone https://github.com/frappe/frappe --branch "${BRANCH_NAME}"
bench init frappe-bench --frappe-path ~/frappe --python "$(which python)" --skip-assets --ignore-exist

mkdir ~/frappe-bench/sites/test_site
cp -r "${GITHUB_WORKSPACE}/.github/helper/site_config.json" ~/frappe-bench/sites/test_site/

cd ~/frappe-bench || exit

sed -i 's/watch:/# watch:/g' Procfile
sed -i 's/schedule:/# schedule:/g' Procfile
sed -i 's/socketio:/# socketio:/g' Procfile
sed -i 's/redis_socketio:/# redis_socketio:/g' Procfile

bench get-app https://github.com/frappe/erpnext --branch "${BRANCH_NAME}" --resolve-deps --skip-assets
bench get-app beam "${GITHUB_WORKSPACE}" --skip-assets --resolve-deps

printf '%s\n' 'frappe' 'erpnext' 'beam' > ~/frappe-bench/sites/apps.txt
bench setup requirements --python
bench use test_site

bench start &> bench_run_logs.txt &
CI=Yes &
bench --site test_site reinstall --yes --admin-password admin

# bench --site test_site install-app erpnext beam
bench setup requirements --dev

echo "BENCH VERSION NUMBERS:"
bench version
echo "SITE LIST-APPS:"
bench list-apps

bench start &> bench_run_logs.txt &
CI=Yes &
bench execute 'beam.tests.setup.before_test'
