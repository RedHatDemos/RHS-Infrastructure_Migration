#!/bin/bash

DOWNLOAD_PATH='/var/www/html/repos'
REPO_CONFIG='/root/reposync/redhat.repo'

reposync --download_path=${DOWNLOAD_PATH} \
    --config=${REPO_CONFIG} \
    --download-metadata \
    --downloadcomps \
    --delete \
    --newest-only

for REPODIR in $(ls ${DOWNLOAD_PATH}) ; do
    cd ${DOWNLOAD_PATH}/$REPODIR
    createrepo .
    mv -fv productid ./repodata/
    mv -fv *.xml* ./repodata/
done
