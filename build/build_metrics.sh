#!/bin/bash -ev
export DISTRO=$(cat /etc/*-release|grep ^ID\=|awk -F\= {'print $2'}|sed s/\"//g)

if [[ "${DISTRO}" == "ubuntu" ]]; then
    apt-get install -y apt-transport-https curl
fi

[[ -z ${MIRROR_BUILD_DIR} ]] && export MIRROR_BUILD_DIR=${PWD}
[[ -z ${MIRROR_OUTPUT_DIR} ]] && export MIRROR_OUTPUT_DIR=${PWD}/mirror_metrics

STATIC_FILE_LIST=$(<${MIRROR_BUILD_DIR}/dependencies/pnda-metrics-file-dependencies.txt)

STATIC_FILE_DIR=$MIRROR_OUTPUT_DIR
mkdir -p $STATIC_FILE_DIR
cd $STATIC_FILE_DIR
echo "$STATIC_FILE_LIST" | while read STATIC_FILE
do
    echo -e "\n***************Downloading Files *****************"
    echo -e "$STATIC_FILE\n"

    ATTEMPT=0
    RETRY=3
    until [[ ${ATTEMPT} -ge ${RETRY} ]]
    do
        curl -LOJf $STATIC_FILE && break
        ATTEMPT=$[${ATTEMPT}+1]
        sleep 10
    done

    if [[ ${ATTEMPT} -ge ${RETRY} ]]; then
        echo "Failed to download ${STATIC_FILE} after ${RETRY} retries"
        exit -1
    fi
done
