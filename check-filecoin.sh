#!/bin/bash
# Filecoin auto-deployment script.
# Written by Leng Bo <lengbo@storswift.com>
# License:
# 1. Please keep the author name and email address when you use or
#    redistribute in code when you use it.
# 2. This file is under MIT license.

BINDIR=/usr/bin
WORKDIR=/mnt/filecoin
FILECOIN_REPO=${WORKDIR}/devnet/repo
LOGDIR=${WORKDIR}/log
CHKFLAG=/tmp/__check_filecoin_flag__

if [ -f ${CHKFLAG} ]; then
    exit 1
fi
touch ${CHKFLAG}
trap 'rm -f ${CHKFLAG} 1>/dev/null 2>&1' 0
trap 'rm -f ${CHKFLAG} 1>/dev/null 2>&1;exit 1' SIGHUP SIGINT SIGQUIT SIGTERM

mkdir -p ${LOGDIR}

# echo 3 >/proc/sys/vm/drop_caches

PREV_PID=`ps -ef | grep "go-filecoin --repodir=${FILECOIN_REPO} daemon" |grep -v grep | awk '{print $2}'`
if [ "${PREV_PID}" = "" ]; then
    logger "Restart filecoin daemon."
    nohup ${BINDIR}/go-filecoin --repodir=${FILECOIN_REPO} daemon 1>${LOGDIR}/filecoin_`date +%Y%m%d%H%M`.log 2>&1 &
fi

MINING_STATUS=`go-filecoin --repodir=${FILECOIN_REPO}  mining status | grep Active | awk '{print $2}'`
while [ "${MINING_STATUS}" != "true" ]; do
    ${BINDIR}/go-filecoin --repodir=${FILECOIN_REPO} mining start 1>>${LOGDIR}/mining_status 2>&1
    sleep 1
    PREV_PID=`ps -ef | grep "go-filecoin --repodir=${FILECOIN_REPO} daemon" |grep -v grep | awk '{print $2}'`
    if [ "${PREV_PID}" = "" ]; then
        logger "Filecoin daemon crashes. Please check."
        exit 1
    fi
    MINING_STATUS=`go-filecoin --repodir=${FILECOIN_REPO}  mining status | grep Active | awk '{print $2}'`
done
