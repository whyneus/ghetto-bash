#!/bin/bash

if [[ -z ${2} ]]
then
  echo "Usage: ${0} <client.domain.ad> <remote-netbios-name> <username> <password>"
  exit 1
fi

while pgrep -x "yum" > /dev/null
do
  sleep 10
done

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
  distro_ver=$(rpm -q --qf '%{VERSION}' $RELEASERPM)
else
  distro_name=`lsb_release -si`
  distro_ver=`lsb_release -rs | cut -d\. -f1`
  if [[ $distro_name != "Ubuntu" ]]
  then
    echo "Only Red Hat, CentOS and Ubuntu operating systems are suported." >> /root/adclog-`date +%Y%m%d`
    exit 1
  fi
fi

realmupper=`echo ${1} | tr '[:lower:]' '[:upper:]'`
realmlower=`echo ${1} | tr '[:upper:]' '[:lower:]'`
netbiosnameupper=`hostname -s | tr '[:lower:]' '[:upper:]' | cut -c 1-15`
netbiosnamelower=`hostname -s | tr '[:upper:]' '[:lower:]' | cut -c 1-15`
adnetbiosnameupper=`echo ${2} | tr '[:lower:]' '[:upper:]'`

case $distro_name in
  RHEL|CentOS*)
    if [[ $distro_ver -eq 6 ]]
    then
      # TODO
      exit 1
    elif [[ $distro_ver -eq 7 ]]
    then
      yum -q -y install authconfigkrb5-workstation ntp openldap-clients samba-common sssd sssd-tools 2>&1 >/dev/null
      systemctl stop sssd
      rm -f /var/lib/sss/db/* /var/lib/sss/mc/*
      systemctl start ntpd; systemctl stop nslcd winbind nscd
      systemctl enable ntpd.service; systemctl disable nslcd winbind nscd
    fi

    echo "[global]
 security = ads
 realm = ${realmupper}
 workgroup = ${adnetbiosnameupper}
 netbios name = ${netbiosnameupper}
 log file = /var/log/samba/%m.log
 kerberos method = secrets and keytab
 client signing = yes
 client use spnego = yes" > /etc/samba/smb.conf

    echo "[logging]
 default = FILE:/var/log/krb5libs.log

[libdefaults]
 default_realm = ${realmupper}
 dns_lookup_realm = true
 dns_lookup_kdc = true
 ticket_lifetime = 24h
 renew_lifetime = 7d
 rdns = false
 forwardable = yes

[domain_realm]
 .${realmlower} = ${realmupper}
 ${realmlower} = ${realmupper}" > /etc/krb5.conf

      echo ${4} | kinit ${3}@${realmupper}
      net ads join -U ${3}%${4}

      touch /etc/sssd/sssd.conf
      chmod 0600 /etc/sssd/sssd.conf

      echo "[sssd]
config_file_version = 2
domains = ${realmupper}
services = nss, pam

[domain/${realmupper}]
id_provider = ad
access_provider = ad
fallback_homedir = /home/%u
override_shell = /bin/bash
dns_discovery_domain = ${realmupper}" > /etc/sssd/sssd.conf

  echo -e "%${realmupper}\\\\\\Domain\ Admins\t\tALL=(ALL)\tALL\n%${realmupper}\\\\\\\\Enterprise\ Admins\tALL=(ALL)\tALL" > /etc/sudoers.d/domainadmins

  if [[ $distro_ver -eq 6 ]]
  then
    # TODO
    exit 1
  elif [[ $distro_ver -eq 7 ]]
  then
    systemctl start sssd ; systemctl enable sssd
    authconfig --update --enablesssd --enablesssdauth --enablemkhomedir --disableldap --disableldapauth --disablekrb5 --disablewinbind --disablewinbindauth --disablefingerprint
    echo "ENABLEMKHOMEDIR=yes" >> /etc/sysconfig/authconfig
    authconfig --update
  fi
  ;;
  Ubuntu)
    # TODO
    exit 1
    ;;
esac
