#!/bin/bash

set -o errexit
set -o pipefail

# Add the current directory to our virtualenv
python setup.py develop

# Utilize paster command, can remove when on ckan 2.9
function ckan () {
    paster --plugin=ckan "$@"
}

function vcap_get_service () {
  local path service_name
  service_name="$1"
  path="$2"
  echo $VCAP_SERVICES | jq --raw-output --arg service_name "$service_name" ".[][] | select(.name == \$service_name) | $path"
}

# Create a staging area for secrets and files
CONFIG_DIR=$(mktemp -d)
SHARED_DIR=$(mktemp -d)

# We need to know the application name ...
APP_NAME=$(echo $VCAP_APPLICATION | jq -r '.application_name')
ORG_NAME=$(echo $VCAP_APPLICATION | jq -r '.organization_name')
SPACE_NAME=$(echo $VCAP_APPLICATION | jq -r '.space_name')

# We need the public URL for the configuration file
APP_URL=$(echo $VCAP_APPLICATION | jq -r '.application_uris[0]')

# ... from which we can guess the service names

SVC_DATABASE="${APP_NAME}-db"
SVC_DATASTORE="${APP_NAME}-datastore"
SVC_S3="${APP_NAME}-s3"
SVC_REDIS="${APP_NAME}-redis"
SVC_SECRETS="${APP_NAME}-secrets"

# We need specific datastore URL components so we can construct another URL for the read-only user
DS_HOST=$(vcap_get_service $SVC_DATASTORE .credentials.host)
DS_PORT=$(vcap_get_service $SVC_DATASTORE .credentials.port)
DS_DBNAME=$(vcap_get_service $SVC_DATASTORE .credentials.db_name)

# We need the redis credentials for ckan to access redis, and we need to build the url to use the rediss
REDIS_HOST=$(vcap_get_service $SVC_REDIS .credentials.host)
REDIS_PASSWORD=$(vcap_get_service $SVC_REDIS .credentials.password)
REDIS_PORT=$(vcap_get_service $SVC_REDIS .credentials.port)

SAML2_PRIVATE_KEY=$(vcap_get_service $SVC_SECRETS .credentials.SAML2_PRIVATE_KEY)

export CKANEXT__SAML2AUTH__KEY_FILE_PATH=${CONFIG_DIR}/saml2_key.pem
export CKANEXT__SAML2AUTH__CERT_FILE_PATH=${CONFIG_DIR}/saml2_certificate.pem

# We need the secret credentials for various application components (DB configuration, license keys, etc)
DS_RO_PASSWORD=$(vcap_get_service $SVC_SECRETS .credentials.DS_RO_PASSWORD)
export NEW_RELIC_LICENSE_KEY=$(vcap_get_service $SVC_SECRETS .credentials.NEW_RELIC_LICENSE_KEY)
export CKAN___BEAKER__SESSION__SECRET=$(vcap_get_service $SVC_SECRETS .credentials.CKAN___BEAKER__SESSION__SECRET)

# ckan reads some environment variables... https://docs.ckan.org/en/2.8/maintaining/configuration.html#environment-variables
export CKAN_SQLALCHEMY_URL=$(vcap_get_service $SVC_DATABASE .credentials.uri)
export CKAN___BEAKER__SESSION__URL=${CKAN_SQLALCHEMY_URL}
export CKAN_SITE_URL=https://$APP_URL
export CKAN_SITE_ID=$ORG_NAME-$SPACE_NAME-$APP_NAME
export CKAN_SOLR_URL=$SOLR_URL
export CKAN_DATASTORE_WRITE_URL=$(vcap_get_service $SVC_DATASTORE .credentials.uri)
export CKAN_DATASTORE_READ_URL=postgres://$DS_RO_USER:$DS_RO_PASSWORD@$DS_HOST:$DS_PORT/$DS_DBNAME
export CKAN_REDIS_URL=rediss://:$REDIS_PASSWORD@$REDIS_HOST:$REDIS_PORT
export CKAN_STORAGE_PATH=${SHARED_DIR}/files

# Use ckanext-envvars to import other configurations...
export CKANEXT__S3FILESTORE__REGION_NAME=$(vcap_get_service $SVC_S3 .credentials.region)
export CKANEXT__S3FILESTORE__HOST_NAME=https://s3-$CKANEXT__S3FILESTORE__REGION_NAME.amazonaws.com
export CKANEXT__S3FILESTORE__AWS_ACCESS_KEY_ID=$(vcap_get_service $SVC_S3 .credentials.access_key_id)
export CKANEXT__S3FILESTORE__AWS_SECRET_ACCESS_KEY=$(vcap_get_service $SVC_S3 .credentials.secret_access_key)
export CKANEXT__S3FILESTORE__AWS_BUCKET_NAME=$(vcap_get_service $SVC_S3 .credentials.bucket)

# Write out any files and directories
mkdir -p $CKAN_STORAGE_PATH
echo "$SAML2_PRIVATE_KEY" | base64 -d > $CKANEXT__SAML2AUTH__KEY_FILE_PATH
echo "$SAML2_CERTIFICATE" > $CKANEXT__SAML2AUTH__CERT_FILE_PATH

# Edit the config file to use validate debug is off and utilizes the correct port
export CKAN_INI=config/production.ini
ckan config-tool $CKAN_INI -s server:main -e port=${PORT}
ckan config-tool $CKAN_INI -s DEFAULT -e debug=false

echo "Setting up the datastore user"
DATASTORE_URL=$CKAN_DATASTORE_WRITE_URL DS_RO_USER=$DS_RO_USER DS_RO_PASSWORD=$DS_RO_PASSWORD ./datastore-usersetup.py

# Run migrations
# paster --plugin=ckan db upgrade -c config/production.ini
ckan db upgrade -c $CKAN_INI

# Fire it up!
exec config/server_start.sh -b 0.0.0.0:$PORT -t 9000
