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

mkdir -p ${LOGDIR}

# echo 3 >/proc/sys/vm/drop_caches

PREV_PID=`ps -ef | grep "go-filecoin --repodir=${FILECOIN_REPO}" |grep -v grep | awk '{print $2}'`
if [ "${PREV_PID}" = "" ]; then
    logger "Restart filecoin daemon."
    nohup ${BINDIR}/go-filecoin --repodir=${FILECOIN_REPO} daemon 1>${LOGDIR}/filecoin_`date +%Y%m%d%H%M`.log 2>&1 &
    sleep 300
    echo `date` >> ${LOGDIR}/mining_status
    ${BINDIR}/go-filecoin --repodir=${FILECOIN_REPO} mining start 1>>${LOGDIR}/mining_status 2>&1
fi
