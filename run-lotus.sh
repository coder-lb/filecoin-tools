#!/bin/bash
# Filecoin auto-deployment script.
# Written by Leng Bo <lengbo@storswift.com>
# License:
# 1. Please keep the author name and email address when you use or
#    redistribute in code when you use it.
# 2. This file is under MIT license.

BINDIR=/usr/bin
LOTUS_BINDIR=/usr/local/bin
WORKDIR=/mnt/lotus
FILECOIN_REPO=/mnt/lotus/.lotus
FILECOIN_STORAGE=/mnt/lotus/.lotusstorage
PROOF_PARAMETERS=/var/tmp/filecoin-proof-parameters

BUILD_LOTUS=0 # Set it to 1 to build lotus manually

GOLANG_TAR=go1.13.3.linux-amd64.tar.gz
GOLANG_TAR_URL=https://dl.google.com/go/${GOLANG_TAR}
LOTUS_GIT=https://github.com/filecoin-project/lotus.git

LOTUS_FAUCET=https://lotus-faucet.kittyhawk.wtf/send?address=

CURRENT_LOTUS_VERSION=lotus-devnet6
CURRENT_LOTUS_TAR=${CURRENT_LOTUS_VERSION}.tar.gz
LOTUS_BINARY_URL=https://storswift.com/download/lotus/${CURRENT_LOTUS_TAR}

function show_error()
{
    echo "****************************************"
    echo $1
    echo "****************************************"
    exit 1
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
        sudo apt-get update
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

function build_lotus()
{
    # Install golang
    go version
    # TODO: Check go version
    if [ $? -ne 0 ]; then
        curl -O ${GOLANG_TAR_URL} || show_error "Golang package can't be downloaded!"
        tar zxvf ${GOLANG_TAR} || show_error "Golang package can't be decompressed!"
        sudo ln -s ${WORKDIR}/go/bin/go ${BINDIR}/go
        export GOROOT=${WORKDIR}/go
        export PATH=${PATH}:${GOROOT}/bin
        mkdir -p ${WORKDIR}/gopath
        export GOPATH=${WORKDIR}/gopath
    fi

    lotus >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        FILECOIN_PROJECT_PATH=github.com/filecoin-project
        cd ${WORKDIR}/gopath
        mkdir -p ${FILECOIN_PROJECT_PATH}
        cd ${FILECOIN_PROJECT_PATH}
        git clone ${LOTUS_GIT}
        cd lotus/
        make || show_error "It can't build lotus!"
        sudo make install || show_error "It can't install lotus!"
        
        #sudo apt install npm
        #make pond
        #./pond run
    fi
}


function download_lotus()
{
    curl -O ${LOTUS_BINARY_URL} || show_error "Lotus package can't be downloaded!"
    tar zxvf ${CURRENT_LOTUS_TAR} || show_error "Lotus package can't be decompressed!"
    chmod +x ${CURRENT_LOTUS_VERSION}/lotus
    chmod +x ${CURRENT_LOTUS_VERSION}/lotus-storage-miner

    sudo cp -f ${CURRENT_LOTUS_VERSION}/lotus ${LOTUS_BINDIR} || \
        show_error "Error occurs during coping lotus!"
    sudo cp -f ${CURRENT_LOTUS_VERSION}/lotus-storage-miner ${LOTUS_BINDIR} ||  \
        show_error "Error occurs during coping lotus-storage-miner!"
}

# Regular check
if [ "${LOGDIR}" = "" ]; then
    LOGDIR=${WORKDIR}/log
fi
mkdir -p ${LOGDIR}

Get_Dist_Name
sudo ${PM} -y install bzr
if [ "${DISTRO}" = "Ubuntu" ]; then
    sudo  ${PM} -y install pkg-config
fi

cd ${WORKDIR}


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
    rm -rf ${FILECOIN_REPO}
    rm -rf ${FILECOIN_STORAGE}
fi

mkdir -p ${FILECOIN_REPO}
mkdir -p ${FILECOIN_STORAGE}
ln -sf ${FILECOIN_REPO} ~/.lotus
ln -sf ${FILECOIN_STORAGE}  ~/.lotusstorage

if [ "${BUILD_LOTUS}" = "1" ]; then
    build_lotus
else
    if [ ! -f ${CURRENT_LOTUS_TAR} ]; then
        download_lotus
    fi
fi

#lotus daemon
CURRENT_TIME=`date +%Y%m%d%H%M`
FILECOIN_LOGFILE=lotus_${CURRENT_TIME}.log
nohup lotus daemon 1>${LOGDIR}/${FILECOIN_LOGFILE} 2>&1 &

sleep 30

WALLET_NUM=`lotus wallet list | wc -l`
if [ "${WALLET_NUM}" == "0" ]; then
    lotus wallet new bls || show_error "The wallet can't be created!"
fi

WALLET_ADDR=`lotus wallet list | head -n 1`
# Get some FILs
curl -s -X GET  ${LOTUS_FAUCET}${WALLET_ADDR}

echo "Now waiting for chain sync. Please use CTRL+C to exit."
echo "The lotus daemon will continue to run after quiting."

watch lotus sync status
