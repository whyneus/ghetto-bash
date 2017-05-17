#!/bin/bash

if [[ -z ${1} ]]
then
  echo -e "Options:\n\t-w Webserver (apache|nginx)\n\t-P Install PHP (none|mod|fpm)\n\t-p PHP Version (CentOS: base|56|70|71) (Ubuntu: base)"
  exit 1
fi

while getopts w:P:p:f: option
do
  case "${option}"
  in
      w) WEBSERVER=${OPTARG};;
      P) PHP=${OPTARG};;
      p) PHPVER=${OPTARG};;
  esac
done


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
  else
    distro_name=`lsb_release -si`
    distro_ver=`lsb_release -rs | cut -d\. -f1`
    if [[ $distro_name != "Ubuntu" ]]
    then
      echo "Only Red Hat, CentOS and Ubuntu operating systems are suported." >> /root/adclog-`date +%Y%m%d`
      exit 1
    fi
  fi
}


function kernel_tuning()
{
  echo "net.core.somaxconn = 1024" >> /etc/sysctl.conf
  sysctl -p
}


function install_apache()
{
  case ${distro_name} in
    RHEL|CentOS*)
      yum -q -y install httpd mod_ssl

      if [[ ${distro_ver} -eq 7 ]]
      then
        echo "ServerTokens Prod" >> /etc/httpd/conf/httpd.conf
        systemctl enable httpd.service
        systemctl start httpd.service
      elif [[ ${distro_ver} -eq 6 ]]
      then
        sed -i s/^ServerTokens\ OS/ServerTokens\ Prod/g /etc/httpd/conf/httpd.conf
        chkconfig httpd on
        /etc/init.d/httpd start
      fi
      ;;

    Ubuntu)
      apt-get -qq install apache2
      a2enmod ssl
      a2ensite default-ssl

      if [[ ${distro_ver} -eq 16 ]]
      then
        systemctl enable apache2.service
        systemctl restart apache2.service
      elif [[ ${distro_ver} -eq 14 ]]
      then
        update-rc.d apache2 defaults
        service apache2 restart
      fi
      ;;
  esac
}

function install_nginx()
{
  case ${distro_name} in
    RHEL|CentOS*)
      if grep -qi "Red Hat" /etc/redhat-release; then
        echo "[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/rhel/${distro_ver}/\$basearch/
gpgcheck=0
enabled=1" > /etc/yum.repos.d/nginx.repo
      else echo "[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/centos/${distro_ver}/\$basearch/
gpgcheck=0
enabled=1"  > /etc/yum.repos.d/nginx.repo
      fi

      yum -y -q install nginx

      if [[ ${distro_ver} -eq 7 ]]
      then
        systemctl enable nginx.service
        systemctl start nginx.service
      elif [[ ${distro_ver} -eq 6 ]]
      then
        chkconfig nginx on
        /etc/init.d/nginx start
      fi
      ;;

    Ubuntu)
      apt-get -qq install nginx

      if [[ ${distro_ver} -eq 16 ]]
      then
        systemctl enable nginx.service
        systemctl start nginx.service
      elif [[ ${distro_ver} -eq 14 ]]
      then
        update-rc.d nginx defaults
        service nginx start
      fi
      ;;
  esac
}

function install_php()
{
  case ${distro_name} in
    RHEL|CentOS*)
      if [[ ${distro_ver} -eq 7 ]]
      then
        PHPINILOC="/etc"
        TIMEZONE=`timedatectl --no-pager status | grep Time\ zone\: | awk '{print $3}'`
      elif [[ ${distro_ver} -eq 6 ]]
      then
        PHPINILOC="/etc"
        TIMEZONE=`cat /etc/sysconfig/clock | grep ZONE | cut -d\" -f2`
        if [[ -z ${TIMEZONE} ]]
          then
            TIMEZONE="UTC"
        fi
      fi

      if [[ ${PHPVER} = "base" ]]
      then
        if [[ ${distro_ver} -eq 7 ]]
        then
          yum -q -y install php-gd php-mysql php-mcrypt php-xml php-xmlrpc php-mbstring php-soap php-pecl-memcache php-pecl-redis php-pecl-zendopcache
        elif [[ ${distro_ver} -eq 6 ]]
        then
          yum -q -y install php-gd php-mysql php-mcrypt php-xml php-xmlrpc php-mbstring php-soap php-pecl-memcache php-pecl-redis php-pecl-apc
        fi
      elif [[ ${PHPVER} -eq 56 ]]
      then
        yum -q -y install php56u-process php56u-pear php56u-mysqlnd php56u-mcrypt php56u-gd php56u-xml php56u-common php56u-pecl-jsonc php56u-pdo php56u-pecl-redis \
          php56u-opcache php56u-soap php56u-mbstring php56u-xmlrpc php56u-bcmath php56u-cli php56u-pecl-igbinary php56u-pecl-memcache php56u-intl
      elif [[ ${PHPVER} -gt 69 && ${PHPVER} -lt 72 ]]
      then
        yum -q -y install php${PHPVER}u-cli php${PHPVER}u-mysqlnd php${PHPVER}u-intl php${PHPVER}u-common php${PHPVER}u-pdo php${PHPVER}u-xmlrpc php${PHPVER}u-devel \
          php${PHPVER}u-gd php${PHPVER}u-json php${PHPVER}u-soap php${PHPVER}u-gmp php${PHPVER}u-mcrypt php${PHPVER}u-mbstring php${PHPVER}u-xml php${PHPVER}u-bcmath php${PHPVER}u-process php${PHPVER}u-opcache
      fi
      
      if [ ${distro_ver} -eq 6 ] && [ ${PHPVER} = "base" ]
      then
        sed -ri 's/^;?apc.shm_size.*/apc.shm_size=256M/g' /etc/php.d/apc.ini
      else
        sed -ri 's/^;?opcache.memory_consumption.*/opcache.memory_consumption=256/g' /etc/php.d/*opcache.ini
        sed -ri 's/^;?opcache.max_accelerated_files=.*/opcache.max_accelerated_files=16229/g' /etc/php.d/*opcache.ini
      fi
      
      if [ ${PHP} = "mod" ] && [ ${WEBSERVER} = "apache" ] && [ ${PHPVER} != "base" ]
      then
        yum -q -y install mod_php${PHPVER}u
      elif [ ${PHP} = "mod" ] && [ ${WEBSERVER} = "apache" ] && [ ${PHPVER} = "base" ]
      then
        yum -q -y install php
      fi
      
      sed -i 's/^safe_mode =.*/safe_mode = Off/g' /etc/php.ini
      sed -ri "s~^;?date.timezone =.*~date.timezone = ${TIMEZONE}~g" /etc/php.ini
      sed -i 's/^; *realpath_cache_size.*/realpath_cache_size = 128K/g' /etc/php.ini
      sed -i 's/^; *realpath_cache_ttl.*/realpath_cache_ttl = 7200/g' /etc/php.ini
      sed -i 's/^memory_limit.*/memory_limit = 512M/g' /etc/php.ini
      sed -i 's/^max_execution_time.*/max_execution_time = 1800/g' /etc/php.ini
      sed -i 's/^expose_php.*/expose_php = off/g' /etc/php.ini
      
      if [[ ${distro_ver} -eq 7 ]]
      then
        systemctl restart httpd.service
        if [[ ${PHP} = "fpm" ]]
        then
          systemctl restart php-fpm.service
        fi
      elif [[ ${distro_ver} -eq 6 ]]
      then
        /etc/init.d/httpd restart
        if [[ ${PHP} = "fpm" ]]
        then
          /etc/init.d/php-fpm restart
        fi
      fi
      ;;

    Ubuntu)
      if [[ ${distro_ver} -eq 16 ]]
      then
        PHPINILOC="/etc/php/7.0"
        PHPSOCK="/var/run/php/php7.0-fpm.sock"
        PHPMAJOR="7.0"
        TIMEZONE=`timedatectl --no-pager status | grep Time\ zone\: | awk '{print $3}'`
        apt-get -qq install php-gd php-mysql php-mcrypt php-xml php-xmlrpc php-mbstring php-soap php-memcache php-redis php-opcache
        if [[ ${WEBSERVER} = "apache" ]]
        then
          apt-get -qq install libapache2-mod-php
        fi
      elif [[ ${distro_ver} -eq 14 ]]
      then
        PHPINILOC="/etc/php5"
        PHPSOCK="/var/run/php5-fpm.sock"
        PHPMAJOR="5"
        TIMEZONE=`timedatectl --no-pager status | grep Timezone\: | awk '{print $2}'`
        apt-get -qq install php5-gd php5-mysql php5-mcrypt php5-xmlrpc php-soap php5-memcache php5-redis

        if [[ ${WEBSERVER} = "apache" ]]
        then
          apt-get -qq install libapache2-mod-php5
        fi
      fi
      
      if [[ ${PHP} = "fpm" ]]
      then
        sed -ri "s~^;?date.timezone =.*~date.timezone = ${TIMEZONE}~g" ${PHPINILOC}/fpm/php.ini
        sed -i 's/^; *realpath_cache_size.*/realpath_cache_size = 128K/g' ${PHPINILOC}/fpm/php.ini
        sed -i 's/^; *realpath_cache_ttl.*/realpath_cache_ttl = 7200/g' ${PHPINILOC}/fpm/php.ini
        sed -i 's/^max_execution_time.*/max_execution_time = 1800/g' ${PHPINILOC}/fpm/php.ini
        sed -i 's/^expose_php.*/expose_php = off/g' ${PHPINILOC}/fpm/php.ini
      elif [ ${PHP} = "mod" ] && [ ${WEBSERVER} = "apache" ]
      then
        sed -ri "s~^;?date.timezone =.*~date.timezone = ${TIMEZONE}~g" ${PHPINILOC}/apache2/php.ini
        sed -i 's/^; *realpath_cache_size.*/realpath_cache_size = 128K/g' ${PHPINILOC}/apache2/php.ini
        sed -i 's/^; *realpath_cache_ttl.*/realpath_cache_ttl = 7200/g' ${PHPINILOC}/apache2/php.ini
        sed -i 's/^max_execution_time.*/max_execution_time = 1800/g' ${PHPINILOC}/apache2/php.ini
        sed -i 's/^expose_php.*/expose_php = off/g' ${PHPINILOC}/apache2/php.ini
      fi

      if [ ${PHP} = "fpm" ] && [ ${WEBSERVER} = "apache" ]
      then
        apt-get -qq install libapache2-mod-fastcgi
        echo "<IfModule mod_fastcgi.c>
  AddHandler php${PHPMAJOR}-fcgi .php
  Action php${PHPMAJOR}-fcgi /php${PHPMAJOR}-fcgi
  Alias /php${PHPMAJOR}-fcgi /usr/lib/cgi-bin/php${PHPMAJOR}-fcgi
  FastCgiExternalServer /usr/lib/cgi-bin/php${PHPMAJOR}-fcgi -socket ${PHPSOCK} -pass-header Authorization

  <Directory /usr/lib/cgi-bin>
    Require all granted
  </Directory>
</IfModule>" > /etc/apache2/conf-available/php${PHPMAJOR}-fpm.conf
        a2enmod actions fastcgi alias
        a2enconf php${PHPMAJOR}-fpm
        a2dismod php${PHPMAJOR}
      fi

      echo -e "zend_extension=opcache.so
opcache.enable=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=16229
opcache.revalidate_freq=2
opcache.fast_shutdown=1
opcache.validate_timestamps=1" > ${PHPINILOC}/mods-available/opcache.ini

      if [[ ${PHP} = "fpm" ]]
      then
        if [[ ${distro_ver} -eq 16 ]]
        then
          systemctl restart php7.0-fpm.service
        elif [[ ${distro_ver} -eq 14 ]]
        then
          service php5-fpm restart
        fi
      fi

      if [[ ${WEBSERVER} = "apache" ]]
      then
        if [[ ${distro_ver} -eq 16 ]]
        then
          systemctl restart apache2.service
        elif [[ ${distro_ver} -eq 14 ]]
        then
          service apache2 restart
        fi
      fi
      ;;
  esac
}

function install_phpfpm()
{
  case ${distro_name} in
    RHEL|CentOS*)
      if [[ ${PHPVER} = "base" ]]
      then
        yum -q -y install php-fpm
      else
        yum -q -y install php${PHPVER}u-fpm
      fi
      
      if [[ ${distro_ver} -eq 7 ]]
      then
        if [[ ${WEBSERVER} = "apache" ]]
        then
          yum -q -y install php${PHPVER}u-fpm-httpd
          echo "DirectoryIndex index.php" > /etc/httpd/conf.d/php.conf
          systemctl restart httpd.service
        elif [[ ${WEBSERVER} = "nginx" ]]
        then
          yum -q -y install php${PHPVER}u-fpm-nginx
          systemctl restart nginx.service
        fi
      elif [[ ${distro_ver} -eq 6 ]]
      then
        if [[ ${WEBSERVER} = "apache" ]]
        then
          yum -q -y install httpd-devel
          PREPDIR="/root/apachefastcgi"
          mkdir -p $PREPDIR
          GCCINSTALLED=`command -v gcc`
          MAKEINSTALLED=`command -v make`
          if [[ -z ${MAKEINSTALLED} ]] || [[ -z ${GCCINSTALLED} ]]
          then
            yum -q -y install make gcc
          fi
          wget -q -P ${PREPDIR} 'https://github.com/whyneus/magneto-ponies/raw/master/mod_fastcgi-SNAP-0910052141.tar.gz'
          tar -zxC ${PREPDIR} -f ${PREPDIR}/mod_fastcgi-SNAP-0910052141.tar.gz
          cd ${PREPDIR}/mod_fastcgi-*
          make -f Makefile.AP2 top_dir=/usr/lib64/httpd
          cp .libs/mod_fastcgi.so /usr/lib64/httpd/modules/
          echo "LoadModule fastcgi_module /usr/lib64/httpd/modules/mod_fastcgi.so
DirectoryIndex index.php" > /etc/httpd/conf.d/fastcgi.conf
          echo "# mod_fastcgi in use for PHP-FPM. This file here to prevent 'php' package creating new config." > /etc/httpd/conf.d/php.conf
          /etc/init.d/httpd restart
          rm -rf /root/apachefastcgi
        elif [[ ${WEBSERVER} = "nginx" ]]
        then
          yum -q -y install php${PHPVER}u-fpm-nginx
          /etc/init.d/nginx restart
        fi
      fi

      if [[ ${distro_ver} -eq 7 ]]
      then
        systemctl enable php-fpm.service
        systemctl start php-fpm.service
      elif [[ ${distro_ver} -eq 6 ]]
      then
        chkconfig php-fpm on
        /etc/init.d/php-fpm start
      fi
      ;;

    Ubuntu)
      if [[ ${distro_ver} -eq 16 ]]
      then
        apt-get -qq install php-fpm
        systemctl enable php7.0-fpm.service
        systemctl restart php7.0-fpm.service
      elif [[ ${distro_ver} -eq 14 ]]
      then
        apt-get -qq install php5-fpm
        update-rc.d php5-fpm defaults
        service php5-fpm restart
      fi
      ;;
  esac
}


get_osdistro
kernel_tuning

if [[ ${WEBSERVER} = "apache" ]]
then
  install_apache
elif [[ ${WEBSERVER} = "nginx" ]]
then
  install_nginx
fi

if [[ ${PHP} != "none" ]]
then
  if [[ ${PHP} == "fpm" || ${WEBSERVER} == "nginx" ]]
  then
    install_phpfpm
  fi
  install_php
fi
