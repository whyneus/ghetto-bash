#!/bin/bash

if [[ -z ${4} ]]
then
  echo -e "Usage: ${0} <master|slave> <provider> <master ip> <slave ip>\nExample: ${0} master percona 192.168.50.1 192.168.50.1\n\nProviders:\tosdefault\n\t\tpercona"
  exit 1
fi

MASTERIP=${3}
SLAVEIP=${4}
DBPROVIDER=${2}
DRIVE=`cat /etc/my.cnf | grep ^datadir | awk '{print $3}' | cut -d\/ -f1,2,3`
REPPASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n1)


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
    if [ ${distro_ver} -ne 6 ] && [ ${distro_ver} -ne 7 ]
    then
      echo "Version 6 and 7 supported only. Exiting..."
      exit 1
    fi
#  else
#    distro_name=`lsb_release -si`
#    distro_ver=`lsb_release -rs | cut -d\. -f1`
#    if [[ $distro_name != "Ubuntu" ]]
#    then
#      echo "Only Red Hat, CentOS and Ubuntu operating systems are suported." >> /root/adclog-`date +%Y%m%d`
#      exit 1
#    fi
  fi
}

function master_setup()
{
  SID=`echo ${MASTERIP} | cut -d. -f3,4 | sed "s/\.//g"`
  case ${distro_name} in
    RHEL|CentOS)
      if [[ ! -e ${DRIVE}/mysqllogs ]]
      then
        mkdir -p ${DRIVE}/mysqllogs
        chown mysql:mysql ${DRIVE}/mysqllogs
        chmod 755 ${DRIVE}/mysqllogs
      fi
      sed "/^## Replication and PITR/a binlog-format = MIXED\nexpire-logs-days = 4\nlog-bin = ${DRIVE}/mysqllogs/`hostname`-bin-log\nserver-id = ${SID}" /etc/my.cnf -i
      ;;
  esac

  mysql -e "grant replication slave on *.* to replicant@'${SLAVEIP}' identified by '${REPPASS}'"
  
  rm -f /etc/cron.d/holland
}


function slave_setup()
{
  SID=`echo ${SLAVEIP} | cut -d. -f3,4 | sed "s/\.//g"`
  case ${distro_name} in
    RHEL|CentOS)
      if [[ ! -e ${DRIVE}/mysqllogs ]]
      then
        mkdir -p ${DRIVE}/mysqllogs
        chown mysql:mysql ${DRIVE}/mysqllogs
        chmod 755 ${DRIVE}/mysqllogs
      fi
      sed "/^## Replication and PITR/a read-only = 1\nrelay-log = ${DRIVE}/mysqllogs/`hostname`-relay-log\nrelay-log-space-limit = 16G\nserver-id= ${SID}\nreport-host = `hostname`" /etc/my.cnf -i
      ;;
  esac
}


function restart_services()
{
  if [[ ${distro_ver} -eq 7 ]]
  then
    case ${DBPROVIDER} in
      percona)
        systemctl restart mysqld.service
        ;;
      osdefault)
        systemctl restart mariadb.service
        ;;
    esac
  elif [[ ${distro_ver} -eq 6 ]]
  then
    case ${DBPROVIDER} in
      percona)
        /etc/init.d/mysql restart
        ;;
      osdefault)
        /etc/init.d/mysqld restart
        ;;
    esac
  fi
}


function output_files()
{
  mkdir /root/mysqlmastertoslave
  echo ${REPPASS} > /root/mysqlmastertoslave/replicantpass
  mysqldump -A --flush-privileges --master-data=1 > /root/mysqlmastertoslave/masterdump.sql

  tar -zcf /root/mysqlmastertoslave.tar.gz -C /root/ mysqlmastertoslave/
  rm -rf /root/mysqlmastertoslave

  nc -l 3307 < /root/mysqlmastertoslave.tar.gz &
}

function input_files()
{
  curl -o /root/mysqlmastertoslave.tar.gz http://${MASTERIP}:3307/
  tar -zxf /root/mysqlmastertoslave.tar.gz -C /root/

  mysql < /root/mysqlmastertoslave/masterdump.sql
  mysql -e "change master to master_host='${MASTERIP}', master_user='replicant', master_password='`cat /root/mysqlmastertoslave/replicantpass`'"
  mysql -e "start slave"

  rm -rf /root/mysqlmastertoslave*
}


get_osdistro

if [[ ${1} = "master" ]]
then
  master_setup
elif [[ ${1} = "slave" ]]
then
  slave_setup
fi

restart_services

if [[ ${1} = "master" ]]
then
  output_files
elif [[ ${1} = "slave" ]]
then
  input_files
fi
