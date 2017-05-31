#!/bin/bash

if [[ -z ${1} ]]
then
  echo -e "Options:\n\t-c Collation\n\t-p SA Password"
  exit 1
fi

while getopts c:p: option
do
  case "${option}"
  in
      c) COLLATION=${OPTARG};;
      p) SA_PASSWORD=${OPTARG};;
  esac
done

if [[ `cat /proc/meminfo | grep MemTotal | awk 'OFMT="%.0f" {sum=$2/1024}; END {print sum}'` -lt 3250 ]]
then
  echo -e "MSSQL requires a minimum of 3250MB memory.\nExiting..."
  exit 1
fi

function get_osdistro()
{
  if [[ -e /etc/redhat-release ]]; then
    RELEASERPM=$(rpm -qf /etc/redhat-release)
    case $RELEASERPM in
      redhat*)
        distro_name=RHEL
        ;;
      centos*)
        distro_name=CentOS
        ;;
      *)
        echo "Could not determine if OS is RHEL or CentOS from redhat-release package." >> /root/adclog-`date +%Y%m%d`
        exit 1
        ;;
    esac
    distro_ver=$(rpm -q --qf '%{VERSION}' $RELEASERPM | cut -d\. -f1)
    if [[ ${distro_ver} -ne 7 ]]
    then
      echo -e "RHEL/CentOS 7 supported only.\nExiting..."
      exit 1
    fi
  else
    distro_name=`lsb_release -si`
    distro_ver=`lsb_release -rs | cut -d\. -f1`
    if [[ ${distro_ver} -ne 16 ]]
    then
      echo -e "Ubuntu 16 supported only.\nExiting..."
      exit 1
    fi
    if [[ $distro_name != "Ubuntu" ]]
    then
      echo "Only Red Hat, CentOS and Ubuntu operating systems are suported." >> /root/adclog-`date +%Y%m%d`
      exit 1
    fi
  fi
}

function install_mssql()
{
  case ${distro_name} in
    RHEL|CentOS*)
      curl -s -o /etc/yum.repos.d/mssql-server.repo https://packages.microsoft.com/config/rhel/${distro_ver}/mssql-server.repo
      rpm --import https://packages.microsoft.com/keys/microsoft.asc
      ACCEPT_EULA=Y yum install -q -y mssql-server mssql-tools unixODBC-devel
      yum remove -q -y unixODBC-utf16 unixODBC-utf16-devel
      ;;

    Ubuntu)
      curl -s https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
      curl -s https://packages.microsoft.com/config/ubuntu/16.04/mssql-server.list | tee /etc/apt/sources.list.d/mssql-server.list
      # mssql-tools doesn't exist on Ubuntu for some reason
      apt-get update -qq
      apt-get install -qq -y mssql-server unixodbc-dev
      ;;
  esac

  SA_PASSWORD=${SA_PASSWORD} /opt/mssql/bin/mssql-conf -n setup

  if [[ ! -z ${COLLATION} ]]
  then
    echo ${COLLATION} | /opt/mssql/bin/mssql-conf set-collation
    systemctl restart mssql-server.service
  fi
}

get_osdistro
install_mssql
