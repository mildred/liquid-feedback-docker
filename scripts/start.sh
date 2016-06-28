#! /bin/bash

set -e

if [ -n "$DB_NAME" ]; then
        : ${DB_ENGINE:=postgresql}
        : ${DB_NAME:=lf}
        : ${DB_USER:=postgres}
        : ${DB_HOST:=db}
        : ${DB_PASS:=postgres}
        sed -i -re "s/^(config.database = ).*$/\1{ engine='${DB_ENGINE}', dbname='${DB_NAME}', user='${DB_USER}', host='${DB_HOST}', password='${DB_PASS}' }/" /opt/lf/frontend/config/lfconfig.lua
        psql(){
                PGPASSWORD="$DB_PASS" command psql -h "$DB_HOST" -d "$DB_NAME" -U "$DB_USER" "$@"
        }

        echo "Waiting for the database to settle..."
        while ! psql -c 'select 1;'>/dev/null; do
                echo "exit status $?"
                sleep 1
        done
        echo "Database ready"

        version=$(psql -d lf -U postgres -c 'select string from liquid_feedback_version' -t | xargs)
        if [ -n "$version" ]; then
                echo "Database is at version $version."
                if [ "$LF_CORE_VERSION" != "$version" ]; then
                        echo "Database needs manual upgrade to version $LF_CORE_VERSION" >&2
                        exit 1
                fi
        else
                echo "Setting up the database"
                psql -v ON_ERROR_STOP=1 -f /opt/lf/core.sql
                if [ -n "$INVITE_CODE" ]; then
                echo "Create admin user with invite code '$INVITE_CODE'"
                psql -c "INSERT INTO member (login, name, admin, invite_code) VALUES ('admin', 'Administrator', TRUE, '${INVITE_CODE//"'"/"''"}');"
                fi
        fi

fi

if [ -n "$SMTP_HOST" ]; then
        sed -i -re "s/^mailhub=.*\$/mailhub=$SMTP_HOST/" /etc/ssmtp/ssmtp.conf
fi
if [ -n "$LF_HOSTNAME" ]; then
        sed -i -re "s/^hostname=.*\$/hostname=${LF_HOSTNAME%:*}/" /etc/ssmtp/ssmtp.conf
        sed -i -re "s|^(config.absolute_base_url = ).*$|\1'http://$LF_HOSTNAME/'|" /opt/lf/frontend/config/lfconfig.lua
fi

ln -sf /usr/sbin/sendmail /usr/bin/sendmail

if [ -z "$1" ] ; then
        #service exim4 start
        if [ -z "$DB_NAME" ]; then
                service postgresql start
        fi
        #service lighttpd start

        /opt/lf/bin/lf_updated &

        su -s /bin/sh -l www-data -c '
        cd /opt/lf/frontend
        exec /opt/lf/moonbridge/moonbridge /opt/lf/webmcp/bin/mcp.lua /opt/lf/webmcp/ /opt/lf/frontend/ main lfconfig
        '

        #while true; do sleep 60; done

else
        exec "$@"
fi

