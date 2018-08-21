#!/bin/bash

DOWNLOAD_PATH='/var/www/html/repos'

echo " --- "
echo " Configuring repos to be synced"
echo " --- "
subscription-manager repos --disable='*'\
                           --enable='rhel-7-server-rpms'\
                           --enable='rhel-7-server-extras-rpms'\
                           --enable='rhel-7-server-optional-rpms'\
                           --enable='rhel-7-server-rhv-4-mgmt-agent-rpms'\
                           --enable='rhel-7-server-source-rpms'\
                           --enable='rhel-7-server-ansible-2-rpms'\
                           --enable='rhel-7-server-rh-common-rpms' 

echo " --- "
echo " Sync repos "
echo " --- "
reposync --download_path=${DOWNLOAD_PATH} \
    --download-metadata \
    --downloadcomps \
    --delete \
    --newest-only

for REPODIR in $(ls ${DOWNLOAD_PATH} | grep rpms) ; do
    echo " --- "
    echo " Updating ${REPODIR}"
    echo " --- "
    cd ${DOWNLOAD_PATH}/${REPODIR}
    mv -fv productid ./repodata/
    mv -fv *.xml* ./repodata/
    createrepo .
done

echo " --- "
echo " Reconfiguring repos "
echo " --- "
subscription-manager repos --disable='*' --enable='rhel-7-server-rpms' 

