#!/usr/bin/env bash

# Start the cron service for DSpace's scheduled maintenance tasks
# See: /etc/cron.d/dspace-maintenance-tasks
service cron start

POSTGRES_DB_HOST=${POSTGRES_DB_HOST:-$POSTGRES_PORT_5432_TCP_ADDR}
POSTGRES_DB_PORT=${POSTGRES_DB_PORT:-$POSTGRES_PORT_5432_TCP_PORT}
POSTGRES_DB_PORT=${POSTGRES_DB_PORT:-5432}
DSPACE_HOSTNAME=${DSPACE_HOSTNAME:-localhost}
SPACE_PROXY_PORT=${DSPACE_PROXY_PORT:-8080}
# Create PostgreSQL user and database schema
if [ -n $POSTGRES_DB_HOST -a -n $POSTGRES_DB_PORT ]; then
    # Wait for PostgreSQL and then call `setup-postgres.sh` script
    # See: https://docs.docker.com/compose/startup-order/
    wait-for-postgres.sh $POSTGRES_DB_HOST setup-postgres.sh
fi

if [ -f "/tmp/dspace/local.cfg" ]; then
    echo "Changing local.cgf to fit our configuration..."
    sed -i -e "s/DSPACE_HOSTNAME/$DSPACE_HOSTNAME/" -e "s/DSPACE_PROXY_PORT/$DSPACE_PROXY_PORT/" /tmp/dspace/local.cfg
    sed -i "s#^dspace.dir=.*#dspace.dir=$DSPACE_INSTALL#" /tmp/dspace/local.cfg
    sed -i "s#^dspace.url = \$\{dspace.baseUrl\}/.*#dspace.url = \$\{dspace.baseUrl\}/xmlui#" /tmp/dspace/local.cfg
    sed -i "s#^db.username =.*#db.username =dspace#" /tmp/dspace/local.cfg
    sed -i "s#^db.password =.*#db.password =dspace#" /tmp/dspace/local.cfg
    sed -i "s#^db.url =.*#db.url =jdbc:postgresql://$POSTGRES_DB_HOST:$POSTGRES_DB_PORT/dspace#" /tmp/dspace/local.cfg
    chown -R dspace:dspace "/tmp/dspace" 
fi
#if staistics/data was mounted as a volume, then change permissions to dspace:dspace user and group
if [ -d "/dspace/solr/statistics/data" ]; then
    echo "Changing user permissions user over /dspace/solr/statistics/data directory..."
    chown -R dspace:dspace "/dspace/solr/statistics/data"
fi

exec su - dspace -c "$CATALINA_HOME/bin/catalina.sh run"
