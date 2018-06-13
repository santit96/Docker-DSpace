#!/usr/bin/env bash
set -e

POSTGRES_DB_HOST=${POSTGRES_DB_HOST:-$POSTGRES_PORT_5432_TCP_ADDR}
POSTGRES_DB_PORT=${POSTGRES_DB_PORT:-$POSTGRES_PORT_5432_TCP_PORT}
POSTGRES_DB_PORT=${POSTGRES_DB_PORT:-5432}
POSTGRES_USER=${POSTGRES_USER:-dspace}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-dspace}
POSTGRES_SCHEMA=${POSTGRES_SCHEMA:-dspace}
POSTGRES_ADMIN_USER=${POSTGRES_ADMIN_USER:-postgres}
POSTGRES_ADMIN_PASSWORD=${POSTGRES_ADMIN_PASSWORD}
SQL_IMPORT_FILE=${POSTGRES_SQL_IMPORT_FILE:-/tmp/dspace_data.sql}

if [ -z $POSTGRES_DB_HOST -a -z $POSTGRES_DB_PORT ]; then
  echo "Please create a postgres container and link it to this one:"
  echo "> docker run -d --name dspace_db postgres"
  echo "> docker run --link dspace_db:postgres -p 8080:8080 1science/dspace setup-postgres"
  exit 1
fi

DSPACE_CFG="/tmp/dspace/local.cfg"
if [ -n $POSTGRES_ADMIN_PASSWORD ]; then
  export PGPASSWORD=$POSTGRES_ADMIN_PASSWORD
fi

# Create database user if it does not exist
USER_EXISTS=$(psql -h "$POSTGRES_DB_HOST" -p "$POSTGRES_DB_PORT" -d postgres -U "$POSTGRES_ADMIN_USER" -c "SELECT 1 FROM pg_roles WHERE rolname='${POSTGRES_USER}';" | grep "1" 2>&1 > /dev/null; echo $?)
if [ $USER_EXISTS -eq 1 ]; then
  #psql -h "$POSTGRES_DB_HOST" -p "$POSTGRES_DB_PORT" -d postgres -U "$POSTGRES_ADMIN_USER" -c "CREATE USER $POSTGRES_USER WITH LOGIN PASSWORD '$POSTGRES_PASSWORD';" 2>&1 > /dev/null
  #psql -h "$POSTGRES_DB_HOST" -p "$POSTGRES_DB_PORT" -U "$POSTGRES_ADMIN_USER" -c "CREATE USER $POSTGRES_USER WITH LOGIN PASSWORD '$POSTGRES_PASSWORD';" 2>&1 > /dev/null
  #psql -h "$POSTGRES_DB_HOST" -p "$POSTGRES_DB_PORT" -d postgres -U "$POSTGRES_ADMIN_USER" -c "GRANT ALL PRIVILEGES ON DATABASE $POSTGRES_SCHEMA to $POSTGRES_USER;" 2>&1 > /dev/null
  #psql -h "$POSTGRES_DB_HOST" -p "$POSTGRES_DB_PORT" -U "$POSTGRES_ADMIN_USER" -c "GRANT ALL PRIVILEGES ON DATABASE $POSTGRES_SCHEMA to $POSTGRES_USER;" 2>&1 > /dev/null
  
  createuser -h "$POSTGRES_DB_HOST" -p "$POSTGRES_DB_PORT" -U "$POSTGRES_ADMIN_USER" -d -R -S "$POSTGRES_USER"
  psql -h "$POSTGRES_DB_HOST" -p "$POSTGRES_DB_PORT" -d postgres -U "$POSTGRES_ADMIN_USER" -c "ALTER USER $POSTGRES_USER WITH PASSWORD  '$POSTGRES_PASSWORD';" 2>&1 > /dev/null
  echo "User '${POSTGRES_USER}' created"
fi

# Create database schema if it does not exist
SCHEMA_EXISTS=$(psql -h "$POSTGRES_DB_HOST" -p "$POSTGRES_DB_PORT" -U "$POSTGRES_ADMIN_USER" -lqt | cut -d \| -f 1 | grep -qw "$POSTGRES_SCHEMA";echo $?)
if [ $SCHEMA_EXISTS -eq 1 ]; then
  #psql -h "$POSTGRES_DB_HOST" -p "$POSTGRES_DB_PORT" -U "$POSTGRES_ADMIN_USER" -c "CREATE DATABASE $POSTGRES_SCHEMA;" 2>&1 > /dev/null
  createdb "$POSTGRES_SCHEMA" -h "$POSTGRES_DB_HOST" -p "$POSTGRES_DB_PORT" -U "$POSTGRES_ADMIN_USER" -O "$POSTGRES_USER" --encoding=UTF8

  echo "Database '${POSTGRES_SCHEMA}' created"

  # Create the pgcrypto extension (for DSpace 6) 
  echo "Creating pgcrypto extension..."
  psql -U "$POSTGRES_ADMIN_USER" -h "$POSTGRES_DB_HOST" -p "$POSTGRES_DB_PORT" -d "$POSTGRES_SCHEMA" -c "CREATE EXTENSION pgcrypto;"
 
  #Import SQL data if exists respecive import SQL data file
  if [ -f "$SQL_IMPORT_FILE" ]; then
    echo "Importing Data from SQL file..."  
    psql -h "$POSTGRES_DB_HOST"  -p "$POSTGRES_DB_PORT" -d "$POSTGRES_SCHEMA" -U "$POSTGRES_ADMIN_USER" -f "$SQL_IMPORT_FILE"
    echo "Assgin imported tables ownership to user '$POSTGRES_USER'..."
     #TABLES
     echo "Updating tables ownership"
     for tbl in `psql -h "$POSTGRES_DB_HOST" -p "$POSTGRES_DB_PORT" -U "$POSTGRES_ADMIN_USER" -qAt -c "select tablename from pg_tables where schemaname = 'public';" $POSTGRES_SCHEMA`; 
     do 
       psql -h "$POSTGRES_DB_HOST"  -p "$POSTGRES_DB_PORT" -d "$POSTGRES_SCHEMA" -U "$POSTGRES_ADMIN_USER" -q -c "ALTER TABLE \"$tbl\" OWNER TO $POSTGRES_USER";
     done
     #SEQUENCES
     echo "Updating sequences ownership"
     for tbl in `psql -h "$POSTGRES_DB_HOST" -p "$POSTGRES_DB_PORT" -U "$POSTGRES_ADMIN_USER" -qAt -c "select sequence_name from information_schema.sequences where sequence_schema = 'public';" $POSTGRES_SCHEMA`; 
     do 
       psql -h "$POSTGRES_DB_HOST"  -p "$POSTGRES_DB_PORT" -d "$POSTGRES_SCHEMA" -U "$POSTGRES_ADMIN_USER" -q -c "ALTER TABLE \"$tbl\" OWNER TO $POSTGRES_USER";
     done
  else
    echo "There no exists a SQL import data file..."
  fi
fi

# Configure database in dspace.cfg
sed -i "s#db.url = jdbc:postgresql://localhost:5432/dspace#db.url = jdbc:postgresql://${POSTGRES_DB_HOST}:${POSTGRES_DB_PORT}/${POSTGRES_SCHEMA}#" ${DSPACE_CFG}
sed -i "s#db.username = dspace#db.username = ${POSTGRES_USER}#" ${DSPACE_CFG}
sed -i "s#db.password = dspace#db.password = ${POSTGRES_PASSWORD}#" ${DSPACE_CFG}
echo "DSpace configuration changed"
