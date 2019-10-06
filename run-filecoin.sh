#!/bin/bash
# Filecoin auto-deployment script.
# Written by Leng Bo <lengbo@storswift.com>
# License:
# 1. Please keep the author name and email address when you use or
#    redistribute in code when you use it.
# 2. This file is under MIT license.

TOOLNAME=$0

################################################################################
### NOTICE
### YOU PBOBABLY NEED TO CHANGE THESE OPTIONS!!!
FILECOIN_VERSION=0.5.6
ASK_PRICE=0.0000000000001
ASK_BLOCK=28800
MINER_CREATE_FIL=100
ALT_SWARM_PORT=6008 # If the default swarm port 6000 is used, then use this prot.
################################################################################

BINDIR=/usr/bin
WORKDIR=/mnt/filecoin
#FILECOIN_REPO=~/.filecoin
FILECOIN_REPO=${WORKDIR}/devnet/repo
FILECOIN_BINDIR=${WORKDIR}/filecoin
PROOF_PARAMETERS=/var/tmp/filecoin-proof-parameters


DEFAULT_NICKNAME="storswift" # The nickname shown in network stats dashboard

# Set network type
NETWORK_TYPE="--devnet-user"
#NETWORK_TYPE="--devnet-staging"

# Set genesis file
#GENESIS_FILE=genesis/genesis.car # localnet
GENESIS_FILE=https://genesis.user.kittyhawk.wtf/genesis.car # devnet
#GENESIS_FILE=https://genesis.staging.kittyhawk.wtf/genesis.car # staging devnet

CHAIN_SYNC_TO_CURRENT_HEIGHT=1  # 1: Wait until syncing to current height. 0: disable the feature.
CHAIN_SYNC_WAIT_SECONDS=60 # If CHAIN_SYNC_TO_CURRENT_HEIGHT=0, wait some seconds before after init.

HEARTBEAT=1
BEAT_TARGET="/dns4/backend-stats.kittyhawk.wtf/tcp/8080/ipfs/QmUWmZnpZb6xFryNDeNU7KcJ1Af5oHy7fB9npU67sseEjR"

export FILPATH=/mnt/filecoin/devnet/repo
export FILECOIN_REPO=${FILPATH}
export HOMEDIR=${HOME} # This needs to be changed in crontab

if [ ! -x ${WORKDIR} ]; then
    echo "Please create ${WORKDIR} and use it as work directory."
    echo "Make sure that this directory is on your data drives."
    echo "And copy this script to ${WORKDIR}."
    exit 1
fi
cd ${WORKDIR}

OFFICIAL_URL="https://github.com/filecoin-project/go-filecoin/releases/download/"
OFFICIAL_BINARY="${OFFICIAL_URL}/${FILECOIN_VERSION}/filecoin-${FILECOIN_VERSION}-Linux.tar.gz"
function download_filecoin()
{
    echo "Now download filecoin (go version)."
    FILECOIN_TAR=`basename ${OFFICIAL_BINARY}`
    wget -t3 -c ${OFFICIAL_BINARY} || show_error "Filecoin can't be downloaded from the official site!" 
    tar zxf ${FILECOIN_TAR} || show_error "The downloadeded file is corrupt!"
    
    chmod +x ${FILECOIN_BINDIR}/go-filecoin
    chmod +x ${FILECOIN_BINDIR}/paramcache
}

function usage()
{
  echo "${TOOLNAME} [NODENAME]"
}

function show_error()
{
    echo "****************************************"
    echo $1
    echo "****************************************"
    exit 1
}

# Run it in the background in order to make sure that the user only types one password
SUDO_FLAG="/tmp/sudo_klajslkjdfasdfl"
function sudo_checker()
{
    while [ -f ${SUDO_FLAG} ]; do
        sudo -v
        sleep 10
    done &
}

# From lnmp1.2-full/include/main.sh
function Get_Dist_Name()
{
    if grep -Eqi "CentOS" /etc/issue || grep -Eq "CentOS" /etc/*-release; then
        DISTRO='CentOS'
        PM='yum'
    elif grep -Eqi "Red Hat Enterprise Linux Server" /etc/issue || \
        grep -Eq "Red Hat Enterprise Linux Server" /etc/*-release; then
        DISTRO='RHEL'
        PM='yum'
    elif grep -Eqi "Aliyun" /etc/issue || grep -Eq "Aliyun" /etc/*-release; then
        DISTRO='Aliyun'
        PM='yum'
    elif grep -Eqi "Fedora" /etc/issue || grep -Eq "Fedora" /etc/*-release; then
        DISTRO='Fedora'
        PM='yum'
    elif grep -Eqi "Debian" /etc/issue || grep -Eq "Debian" /etc/*-release; then
        DISTRO='Debian'
        PM='apt'
    elif grep -Eqi "Ubuntu" /etc/issue || grep -Eq "Ubuntu" /etc/*-release; then
        DISTRO='Ubuntu'
        PM='apt'
    elif grep -Eqi "Raspbian" /etc/issue || grep -Eq "Raspbian" /etc/*-release; then
        DISTRO='Raspbian'
        PM='apt'
    elif grep -Eqi "Storswift" /etc/issue || grep -Eq "Storswift" /etc/*-release; then
        DISTRO='StorSwiftOS'
        PM='yum'
    else
        DISTRO='unknow'
    fi
}

GLIBC_218_FILE="/usr/lib64/libc-2.18.so"
function prepare()
{
    echo "Recommended OS for filecoin: "
    echo "  Ubuntu Server 18.04"
    echo "  RHEL/CentOS 7.6"
    echo "  StorSwift OS 2.1"
    echo "If you run other Linux distributions, you NEED to solve additional problems."
    echo
    sleep 2

    # Install necessary packages
    Get_Dist_Name
    
    if [[ "${DISTRO}" = "CentOS" || "${DISTRO}" = "RHEL" || "${DISTRO}" = "StorSwiftOS" ]]; then
        sudo yum -y install epel-release
        if [ ! -f "${GLIBC_218_FILE}" ]; then
            # For CentOS 7.x, RHEL 7.x, StorSwift OS 2.x
            # glibc needs to be upgraded to 2.18
            sudo yum -y install make gcc
            pushd .
            curl -O http://ftp.gnu.org/gnu/glibc/glibc-2.18.tar.gz
            tar zxf glibc-2.18.tar.gz
            cd glibc-2.18/
            mkdir build
            cd build/
            ../configure --prefix=/usr --disable-profile --enable-add-ons --with-headers=/usr/include \
                --with-binutils=/usr/bin
            make -j4 # TODO: How about CPU with less cores?
            sudo make install
            popd
        fi
    fi
    
    sudo ${PM} -y install jq
    sudo ${PM} -y install curl
}

if [ $# -lt 1 ]; then
    NICKNAME=${DEFAULT_NICKNAME}
    echo "Use default NODENAME ${DEFAULT_NICKNAME}."
else
    NICKNAME=$1
    echo "Use NODENAME ${NICKNAME}."
fi

touch ${SUDO_FLAG}
trap 'rm -f ${SUDO_FLAG} 1>/dev/null 2>&1' 0
trap 'rm -f ${SUDO_FLAG} 1>/dev/null 2>&1;exit 1' SIGHUP SIGINT SIGQUIT SIGTERM
sudo -v
sudo_checker

cat  ${HOMEDIR}/.bashrc | grep "alias filecoin"
if [ $? -ne 0 ]; then
    sudo cat >> ${HOMEDIR}/.bashrc <<\EOF
export BINDIR=/usr/bin
export FILPATH=/mnt/filecoin/devnet/repo
export FILECOIN_REPO="$FILPATH"
alias filecoin="go-filecoin --repodir=$FILPATH"
alias chain='filecoin show block `filecoin chain head|head -n 1`;date'
alias fil="filecoin wallet balance `filecoin address ls`;date"
alias miner='filecoin config mining.minerAddress'
alias power='filecoin miner power `filecoin config mining.minerAddress | tr -d \"`'
alias completed='filecoin deals list --miner | grep complete | wc -l'
alias rejected='filecoin deals list --miner | grep rejected | wc -l'
alias staged='filecoin deals list --miner | grep staged | wc -l'
alias status='filecoin mining status'
EOF
fi

# Regular check
if [ "${LOGDIR}" = "" ]; then
    LOGDIR=${WORKDIR}/log
fi
mkdir -p ${LOGDIR}
mkdir -p ${FILECOIN_BINDIR}
mkdir -p ${WORKDIR}/devnet

RUN_FLAG=0

while true
do
    echo
    echo "You can do the following tasks:"
    echo "  1. Create a new filecoin repo, a new miner and start the miner."
    echo "  2. Create a new miner and start the miner."
    echo "  3. Only create an ASK order."
    echo "  4. Only show miner node information."
    read -r -p "Please input your choice: " RUN_FLAG

    case ${RUN_FLAG} in
            [1-4])
                break
                ;;

            *)
                echo "Please input the correct number."
                ;;
            esac
done

if [ ${RUN_FLAG} -le 1 ]; then
    if [ -d ${FILECOIN_REPO} ]; then
        while true
        do
            read -r -p "Are You Sure to remove previous filecoin repo and recreate the node? [yes/no] " input

            case ${input} in
                [yY][eE][sS])
                    echo "You choose 'yes'. Now recreate filecoin node."
                    break
                    ;;

                [nN][oO])
                    echo "You choose 'no'. Now exit."
                    exit 1
                    ;;

                *)
                    echo "Please input yes/no."
                    ;;
            esac
        done
    fi
fi

prepare

if [ ! -x ${FILECOIN_BINDIR}/go-filecoin ]; then
    download_filecoin
fi
sudo ln -sf ${FILECOIN_BINDIR}/go-filecoin ${BINDIR}/go-filecoin

rm -f ${SUDO_FLAG}

if [ ! -d ${PROOF_PARAMETERS} ]; then
    mkdir -p ${PROOF_PARAMETERS}
    if [ ! -x ${FILECOIN_BINDIR}/paramcache ]; then
        show_error "Please put paramcache to ${FILECOIN_BINDIR} and run chmod +x!"
    fi
    echo "Now generate proof parameters. It may take a long time."
    echo ".........."
    ${FILECOIN_BINDIR}/paramcache 
fi


if [ ${RUN_FLAG} -le 1 ]; then
    PREV_PID=`ps -ef | grep "go-filecoin --repodir=${FILECOIN_REPO}" |grep -v grep | awk '{print $2}'`
    if [ "${PREV_PID}" != "" ]; then
        kill ${PREV_PID}
    fi

    rm -rf ${FILECOIN_REPO} || show_error "Can't remove old repo"

    go-filecoin --repodir=${FILECOIN_REPO} init ${NETWORK_TYPE} --genesisfile=${GENESIS_FILE} \
        || show_error "Can't init repo"
        
    sleep 10
    
    CONFLICTED_PORT=`netstat -anp | grep LISTEN | grep 6000`
    if [[ -n "${CONFLICTED_PORT}" ]]; then
        # Replace SWARM port if there are any conflicts.
        # For example, X server may use Port 6000.
        sed -i "s/\/ip4\/0.0.0.0\/tcp\/6000/\/ip4\/0.0.0.0\/tcp\/${ALT_SWARM_PORT}/g" ${FILECOIN_REPO}/config.json \
            || "Can't change API port in ${FILECOIN_REPO}/config.json!"
    fi

    if [ "${HEARTBEAT}" = "1" ]; then
        # Is it better to directly replace strings in config?
        go-filecoin --repodir=${FILECOIN_REPO} daemon &
        sleep 10
        go-filecoin --repodir=${FILECOIN_REPO} config heartbeat.nickname ${NICKNAME}
        go-filecoin --repodir=${FILECOIN_REPO} config heartbeat.beatTarget ${BEAT_TARGET}
        PREV_PID=`ps -ef | grep "go-filecoin --repodir=${FILECOIN_REPO}" |grep -v grep | awk '{print $2}'`
        kill ${PREV_PID}
        sleep 10
    fi

fi

PREV_PID=`ps -ef | grep "go-filecoin --repodir=${FILECOIN_REPO}" |grep -v grep | awk '{print $2}'`
if [ "${PREV_PID}" = "" ]; then
    CURRENT_TIME=`date +%Y%m%d%H%M`
    FILECOIN_LOGFILE=filecoin_${CURRENT_TIME}.log
    echo "Currently there is no filecoin daemon for repo ${FILECOIN_REPO}."
    echo "Now restart the daemon. The log file is ${FILECOIN_LOGFILE}." 
    nohup go-filecoin --repodir=${FILECOIN_REPO} daemon 1>${LOGDIR}/${FILECOIN_LOGFILE} 2>&1 &
    
    sleep 10

    ps -ef | grep go-filecoin | grep -v grep
    if [ $? -ne 0 ]; then
        show_error "Can't start go-filecoin daemon!"
    fi
fi

peerid=$(go-filecoin --repodir=${FILECOIN_REPO} --enc=json id | jq -r '.ID')
walletaddr=`go-filecoin --repodir=${FILECOIN_REPO} address ls`

if [ ${RUN_FLAG} -le 1 ]; then

    sleep 30

    echo "Now wait for chain sync. It may takes hours or days..."
    if [ "${CHAIN_SYNC_TO_CURRENT_HEIGHT}" == "0" ]; then
        sleep ${CHAIN_SYNC_WAIT_SECONDS}
    else
        while :
            do
            # We can adjust the wait time.
            # The server may reset the connection if the frequency is high.
            sleep 300 
            let lastBlockHeight=`curl -s https://backend-stats.kittyhawk.wtf/sync  \
                | jq -r '.mining|.lastBlockHeight'`
            let syncedBlockHeight=`go-filecoin --repodir=${FILECOIN_REPO} show block \
                $(go-filecoin --repodir=${FILECOIN_REPO} chain head | head -n 1) | \
                grep Height  | cut -d " " -f 2`
            echo "(lastBlockHeight, syncedBlockHeight): (${lastBlockHeight},  ${syncedBlockHeight})"
            if [ ${syncedBlockHeight} -ge ${lastBlockHeight} ]; then
                echo "Now syncing has been completed!"
                break;
            fi
        done
    fi
    echo "Now get FIL from the faucet!"

    MESSAGE_CID=`curl -s -X POST -F "target=${walletaddr}" "http://user.kittyhawk.wtf:9797/tap" \
        | cut -d" " -f4`
    echo "Now wait for message with CID ${MESSAGE_CID}"
    go-filecoin --repodir=${FILECOIN_REPO} message wait ${MESSAGE_CID}
    sleep 10
    CURRENT_FIL=`go-filecoin --repodir=${FILECOIN_REPO} wallet balance ${walletaddr}`
    if [ "${CURRENT_FIL}" = "0" ]; then
        echo
        echo
        echo "Can't get FIL! Please visit http://user.kittyhawk.wtf:9797/ to get FIL manually!"
        echo "Wallet Address: ${walletaddr}"
        echo
        echo "And then please run run-filecoin.sh again with Option 2."
        exit 1
    fi
    echo "Now you get FIL: ${CURRENT_FIL}"
fi


if [ ${RUN_FLAG} -le 2 ]; then
    echo "Now create the miner. It may take several minutes."
    go-filecoin --repodir=${FILECOIN_REPO} miner create ${MINER_CREATE_FIL} --gas-price=0.000001 \
         --gas-limit=300 --peerid ${peerid} || show_error "Can't create the miner!"

    go-filecoin --repodir=${FILECOIN_REPO} mining start \
        || show_error "Can't start mining!"
    go-filecoin --repodir=${FILECOIN_REPO} wallet balance ${walletaddr}

    sleep 30
fi

if [ ${RUN_FLAG} -le 3 ]; then
    echo "Now set price for ASK order."
    mineraddr=`go-filecoin --repodir=${FILECOIN_REPO} config mining.minerAddress | tr -d \"` 
    go-filecoin --repodir=${FILECOIN_REPO} miner set-price --from=$walletaddr --miner=${mineraddr} \
        --gas-price=0.001 --gas-limit=1000 ${ASK_PRICE} ${ASK_BLOCK} \
        || show_error "Ask order can't be set!"
    echo "Congratulations! You have successfully set up filecoin miner node!"
fi

if [ ${RUN_FLAG} -le 4 ]; then    
    # Get NICKNAME from config file
    NICKNAME=`go-filecoin --repodir=${FILECOIN_REPO} config heartbeat.nickname | tr -d \"`
    PUBLIC_IP=`curl -s --connect-timeout 5 http://ifconfig.me`
    LOCAL_IP=`/sbin/ifconfig -a|grep inet|grep -v 127.0.0.1|grep -v inet6|awk '{print $2}'|tr -d "addr:"`
    CPU_MODEL=`LC_ALL=C lscpu | grep "Model name"  | cut -f 3- -d " " | awk '{$1=$1};1'`
    CPU_LOGIC_CORES=`lscpu | grep "CPU(s):" | grep -v NUMA | awk '{print $2}'`
    MEM_IN_GB=`free -g | grep Mem | awk '{print $2}'`
    
    if [ -z ${mineraddr} ]; then
        mineraddr=`go-filecoin --repodir=${FILECOIN_REPO} config mining.minerAddress | tr -d \"` 
    fi
    
    echo
    echo "****************************************************************************************"
    echo "NODE: ${NICKNAME}"
    echo "PEERID: ${peerid}"
    echo "PUBLIC IP: ${PUBLIC_IP}"
    echo "LOCAL IP: ${LOCAL_IP}"
    echo "Wallet: ${walletaddr}"
    echo "Miner: ${mineraddr}"
    echo "CPU Model: ${CPU_MODEL}"
    echo "CPU Logic Cores: ${CPU_LOGIC_CORES}"
    echo "RAM Size: ${MEM_IN_GB} GB"
    echo "****************************************************************************************"
    echo
fi
