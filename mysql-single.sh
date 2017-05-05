#!/bin/bash

if [[ -z ${5} ]]
then
  echo -e "Usage: ${0} <provider> <version> <disk> <password> <backupsEnable> <backup:Time>\nExample: ${0} percona 56 datadisk abcd1234\n\nProviders:\tosdefault\n\t\tpercona\n\nVersions:\t56\n\t\t57\n\nDisks:\t\tnone\n\t\tdatadisk"
  exit 1
fi

# Determine which provider
if [[ -n ${1} ]]
then
  if [[ ${1} = "percona" ]]
  then
    DBPROVIDER=${1}
  elif [[ ${1} = "osdefault" ]]
  then
    DBPROVIDER=${1}
  else
    echo "Unknown provider. Exiting..."
    exit 1
  fi
else
  DBPROVIDER="osdefault"
fi

# Determine which version
if [[ -n ${2} ]]
then
  DBVERSION=${2}
else
  DBVERSION=57
fi

# Determine if using data disk
if [ ${3} = "datadisk" ] && [ -e /mnt/disk00 ]
then
  DISK="/mnt/disk00/mysql"
else
  DISK="/var/lib/mysql"
fi

# Grab password or generate one if empty
if [[ -n ${4} ]]
then
  DBPASS=${4}
else
  DBPASS=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n1`
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


function install_mysql()
{
  case ${distro_name} in
    RHEL|CentOS)
      if  [[ ${DBPROVIDER} == "percona" ]]
      then
        yum -y install https://www.percona.com/redir/downloads/percona-release/redhat/latest/percona-release-0.1-4.noarch.rpm
        rpm --import https://www.percona.com/downloads/RPM-GPG-KEY-percona
        yum -y install Percona-Server-server-${DBVERSION} Percona-Server-client-${DBVERSION} Percona-Server-shared-${DBVERSION}
      fi

      if [[ ${DBPROVIDER} == "osdefault" ]]
      then
        if [[ ${distro_ver} -eq 7 ]]
        then
          if [[ ${DBVERSION} -eq 55 ]]
          then
            yum -y install mariadb-server
          elif [[ ${DBVERSION} -eq 56 ]]
          then
            yum -y install yum-plugin-replace
            yum -y replace mariadb-libs --replace-with mariadb100u-libs
            yum -y install mariadb100u-server
          elif [[ ${DBVERSION} -eq 57 ]]
          then
            yum -y install yum-plugin-replace
            yum -y replace mariadb-libs --replace-with mariadb101u-libs
            yum -y install mariadb101u-server
          fi
        elif [[ ${distro_ver} -eq 6 ]]
        then
          if [[ ${DBVERSION} -eq 51 ]]
          then
            yum -y install mysql-server
          elif [[ ${DBVERSION} -eq 55 ]]
          then
            rpm -e --nodeps mysql-libs
            yum -y install mysql55-server mysql55-libs
          elif [[ ${DBVERSION} -eq 56 ]]
          then
            rpm -e --nodeps mysql-libs
            yum -y install mysql56u-server mysql56u-libs
          elif [[ ${DBVERSION} -eq 57 ]]
          then
            rpm -e --nodeps mysql-libs
            yum -y install mysql57u-server mysql57u-libs
          fi
        fi
      fi

      MEMORY=`cat /proc/meminfo | grep MemTotal | awk 'OFMT="%.0f" {sum=$2/1024/1024}; END {print sum}'`
      if [[ ${MEMORY} -lt 7 ]]
      then
        INNODBMEM=`printf "%.0f" $(bc <<< ${MEMORY}*0.75)`G
      else
        INNODBMEM=6G
      fi
      if [[ ${MEMORY} -lt 4 ]]
      then
        INNODBMEM=2G
      fi
      if [[ ${MEMORY} -lt 3 ]]
      then
        INNODBMEM=256M
      fi
      ;;
   esac
}


function configure_mysql()
{
  case ${DBPROVIDER} in
    percona)
      echo "[mysqld]

## General
datadir                              = ${DISK}
socket                               = ${DISK}/mysql.sock
tmpdir                               = /dev/shm

performance-schema              = OFF

## Cache
table-definition-cache               = 4096
table-open-cache                     = 4096
query-cache-size                     = 64M
query-cache-type                     = 1
query-cache-limit                    = 2M


join-buffer-size                    = 2M
read-buffer-size                    = 2M
read-rnd-buffer-size                = 8M
sort-buffer-size                    = 2M

## Temp Tables
max-heap-table-size                 = 96M
tmp-table-size                      = 96M

## Networking
#interactive-timeout                 = 3600
max-connections                      = 500
max-user-connections                 = 400

max-connect-errors                   = 1000000
max-allowed-packet                   = 256M
slave-net-timeout                    = 60
skip-name-resolve
wait-timeout                         = 600

## MyISAM
key-buffer-size                      = 32M
#myisam-recover                      = FORCE,BACKUP
myisam-sort-buffer-size              = 256M

## InnoDB
#innodb-autoinc-lock-mode            = 2
innodb-buffer-pool-size              = ${INNODBMEM}
#innodb-file-format                  = Barracuda
innodb-file-per-table                = 1
innodb-log-file-size                 = 200M

#innodb-flush-method                 = O_DIRECT
#innodb-large-prefix                 = 0
#innodb-lru-scan-depth               = 1000
#innodb-io-capacity                  = 1000
innodb-purge-threads                 = 4
innodb-thread-concurrency            = 32
innodb_lock_wait_timeout             = 300

optimizer_switch                     = 'use_index_extensions=off'
transaction_isolation                = 'READ-COMMITTED'

## Replication and PITR

## Logging
log-output                           = FILE
log-slow-admin-statements
log-slow-slave-statements
#log-warnings                        = 0
long-query-time                      = 4
slow-query-log                       = 1
slow-query-log-file                  = /var/lib/mysqllogs/slow-log

## SSL
#ssl-ca                              = /etc/mysql-ssl/ca-cert.pem
#ssl-cert                            = /etc/mysql-ssl/server-cert.pem
#ssl-key                             = /etc/mysql-ssl/server-key.pem

log-error                            = /var/log/mysqld.log

[mysqld_safe]
log-error                            = /var/log/mysqld.log
open-files-limit                     = 65535

[mysql]
no-auto-rehash" > /etc/my.cnf
    ;;

    osdefault)
      echo "[mysqld]

## General
datadir                         = ${DISK}
tmpdir                          = /dev/shm
socket                          = ${DISK}/mysql.sock
skip-name-resolve
sql-mode                        = NO_ENGINE_SUBSTITUTION
#event-scheduler                = 1

## Cache
thread-cache-size               = 16
table-open-cache                = 4096
table-definition-cache          = 2048
query-cache-size                = 64M
query-cache-limit               = 2M

## Per-thread Buffers
sort-buffer-size                = 2M
read-buffer-size                = 2M
read-rnd-buffer-size            = 4M
join-buffer-size                = 2M

## Temp Tables
tmp-table-size                  = 96M
max-heap-table-size             = 96M

## Networking
back-log                        = 100
#max-connections                = 200
max-connect-errors              = 10000
max-allowed-packet              = 256M
interactive-timeout             = 3600
wait-timeout                    = 600

### Storage Engines
#default-storage-engine         = InnoDB
innodb                          = FORCE

## MyISAM
key-buffer-size                 = 64M
myisam-sort-buffer-size         = 128M

## InnoDB
innodb-buffer-pool-size        = ${INNODBMEM}
innodb-log-file-size           = 200M
#innodb-log-buffer-size         = 8M
innodb-file-per-table          = 1
#innodb-open-files              = 300

## Replication and PITR

## Logging
log-output                      = FILE
slow-query-log                  = 1
slow-query-log-file             = /var/lib/mysqllogs/slow-log
log-slow-slave-statements
long-query-time                 = 4
log-error                       = /var/log/mysqld.log

[mysqld_safe]
log-error                       = /var/log/mysqld.log
open-files-limit                = 65535

[mysql]
no-auto-rehash" > /etc/my.cnf
      ;;
  esac



  mkdir /var/lib/mysqllogs && chown mysql:mysql /var/lib/mysqllogs && chmod 751 /var/lib/mysqllogs

  if [[ ${DISK} == *"disk00"* ]]
  then
    rm -rf /var/lib/mysql
    mkdir /mnt/disk00/mysql
    chown mysql:mysql /mnt/disk00/mysql
    chmod 751 /mnt/disk00/mysql
    ln -s /mnt/disk00/mysql /var/lib/mysql
  else
    rm -rfv /var/lib/mysql/*
  fi

  if [[ ${DBVERSION} -eq 57 ]]
  then
    touch /var/log/mysqld.log && chown mysql:mysql /var/log/mysqld.log && chmod 640 /var/log/mysqld.log
    mysqld --initialize-insecure --user=mysql
  else
    mysql_install_db --user=mysql
  fi

  if [[ ${distro_ver} -eq 7 ]]
  then
    case ${DBPROVIDER} in
      percona)
        systemctl enable mysqld.service
        systemctl start mysqld.service
        ;;
      osdefault)
        sed 's/\/var\/log\/mysqld\.log/\/var\/log\/mariadb\/mysqld\.log/g' /etc/my.cnf -i
        systemctl enable mariadb.service
        systemctl start mariadb.service
        ;;
    esac
  elif [[ ${distro_ver} -eq 6 ]]
  then
    case ${DBPROVIDER} in
      percona)
        chkconfig mysql on
        /etc/init.d/mysql start
        ;;
      osdefault)
        chkconfig mysqld on
        /etc/init.d/mysqld start
        ;;
    esac
  fi

  mysql_upgrade

  case ${DBPROVIDER} in
    percona)
      mysql -uroot --password="" -e "CREATE FUNCTION fnv1a_64 RETURNS INTEGER SONAME 'libfnv1a_udf.so'"
      mysql -uroot --password="" -e "CREATE FUNCTION fnv_64 RETURNS INTEGER SONAME 'libfnv_udf.so'"
      mysql -uroot --password="" -e "CREATE FUNCTION murmur_hash RETURNS INTEGER SONAME 'libmurmur_udf.so'"
      ;;
  esac

  mysql -uroot --password="" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost')"
  mysql -uroot --password="" -e "DELETE FROM mysql.user WHERE User=''"
  mysql -uroot --password="" -e "DROP DATABASE test"
  mysql -uroot --password="" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'"
  mysqladmin -uroot --password="" password ${DBPASS}

  echo "[client]
user=root
password=${DBPASS}
socket=${DISK}/mysql.sock" > /root/.my.cnf
  chmod 600 /root/.my.cnf

  if [[ ${distro_ver} -eq 7 ]]
  then
    if [[ ${DBPROVIDER} = "percona" ]]
    then
      systemctl restart mysqld.service
    else
      systemctl restart mariadb.service
    fi
  elif [[ ${distro_ver} -eq 6 ]]
  then
    if [[ ${DBPROVIDER} = "percona" ]]
    then
      /etc/init.d/mysql restart
    else
      /etc/init.d/mysqld restart
    fi
  fi
}


function install_backup()
{
  yum -y install holland holland-common holland-mysql holland-mysqldump

  echo "[holland:backup]
plugin = mysqldump
backups-to-keep = 5
auto-purge-failures = yes
purge-policy = after-backup
estimated-size-factor = 0.5

# This section defines the configuration options specific to the backup
# plugin. In other words, the name of this section should match the name
# of the plugin defined above.
[mysqldump]
file-per-database       = yes
#lock-method        = auto-detect
#databases          = \"*\"
#exclude-databases  = \"foo\", \"bar\"
#tables             = \"*\"
#exclude-tables     = \"foo.bar\"
#stop-slave         = no
#bin-log-position   = no

# The following section is for compression. The default, unless the
# mysqldump provider has been modified, is to use inline fast gzip
# compression (which is identical to the commented section below).
#[compression]
#method             = gzip
#inline             = yes
#level              = 1

[mysql:client]
defaults-extra-file       = /root/.my.cnf" > /etc/holland/backupsets/default.conf
}


configure_backup()
{
  echo "${BKTIME} * * * root `which holland` -q bk" > /etc/cron.d/holland
}


get_osdistro
install_mysql
configure_mysql
install_backup
if [[ ${5} = "enablebackup" ]]
then
  BKTIME=`echo ${6} | awk -F ":" '{print $2,$1}'`
  configure_backup
fi
