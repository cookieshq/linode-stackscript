#!/bin/bash
# <UDF name="db_password" Label="MySQL root Password" />
# <UDF name="r_env" Label="Rails/Rack environment to run" default="production" />
# <UDF name="ruby_release" Label="Ruby Release" default="2.0.0-p247" example="2.0.0-p247" />
# <UDF name="deploy_user" Label="Name of deployment user" default="deploy" />
# <UDF name="deploy_password" Label="Password for deployment user" />
# <UDF name="deploy_sshkey" Label="Deployment user public ssh key" />
# <UDF name="new_hostname" Label="Server's hostname" default="appserver" />
# <UDF name="ssh_port" Label="SSH Port" default="22" />

exec &> /root/stackscript.log

source <ssinclude StackScriptID=1>  # Common bash functions
source <ssinclude StackScriptID=123>  # Awesome ubuntu utils script

function log {
  echo "### $1 -- `date '+%D %T'`"
}

function update_ssh_port {
  # Ensure iptables-save persists across reboots
  aptitude -y install iptables-persistent

  sed -i "s/Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
  iptables -A INPUT -p tcp -m tcp --dport $SSH_PORT -j ACCEPT
  iptables-save
}


function system_install_imagemagick {
  apt-get -y install imagemagick
}
function system_install_logrotate {
  apt-get -y install logrotate
}

function set_default_environment {
  cat >> /etc/environment << EOF
  RAILS_ENV=$R_ENV
  RACK_ENV=$R_ENV
EOF
}

function create_deployment_user {
  system_add_user $DEPLOY_USER $DEPLOY_PASSWORD "users,sudo"
  system_user_add_ssh_key $DEPLOY_USER "$DEPLOY_SSHKEY"
  system_update_locale_en_US_UTF_8
}

function install_essentials {
  aptitude -y install build-essential libpcre3-dev libssl-dev libcurl4-openssl-dev libreadline5-dev libxml2-dev libxslt1-dev libmysqlclient-dev openssh-server git-core
  goodstuff
}

function set_nginx_boot_up {
  wget http://pastebin.com/download.php?i=bh7xJ328 -O nginx
  chmod 744 /etc/init.d/nginx
  /usr/sbin/update-rc.d -f nginx defaults
  cat > /etc/logrotate.d/nginx << EOF
/usr/local/nginx/logs/* {
  daily
  missingok
  rotate 52
  compress
  delaycompress
  notifempty
  create 640 nobody root
  sharedscripts
  postrotate
  [ ! -f /user/local/nginx/logs/nginx.pid ] || kill -USR1 `cat /user/local/logs/nginx.pid`
  endscript
}
EOF
}

function set_production_gemrc {
  cat > ~/.gemrc << EOF
verbose: true
bulk_treshold: 1000
install: --no-ri --no-rdoc
benchmark: false
backtrace: false
update: --no-ri --no-rdoc
update_sources: true
EOF
  cp ~/.gemrc $USER_HOME
  chown $USER_NAME:$USER_NAME $USER_HOME/.gemrc
}


log "Updating System..."
system_update

log "Installing essentials...includes goodstuff"
install_essentials

log "Setting hostname to $NEW_HOSTNAME"
system_update_hostname $NEW_HOSTNAME

log "Creating deployment user $DEPLOY_USER"
create_deployment_user

cat >> /etc/sudoers <<EOF
Defaults !secure_path
$DEPLOY_USER ALL=(ALL) NOPASSWD: ALL
EOF


log "Setting basic security settings"
system_security_fail2ban
system_security_ufw_install
system_security_ufw_configure_basic
system_sshd_permitrootlogin No
system_sshd_passwordauthentication No
system_sshd_pubkeyauthentication Yes
/etc/init.d/ssh restart

log "installing log_rotate"
system_install_logrotate

log "Installing and tunning MySQL"
mysql_install "$DB_PASSWORD" && mysql_tune 40

log "Installing RVM and Ruby dependencies" >> $logfile
aptitude -y install git-core libmysqlclient15-dev curl build-essential libcurl4-openssl-dev zlib1g-dev libssl-dev libreadline6 libreadline6-dev libperl-dev gcc libjpeg62-dev libbz2-dev libtiff4-dev libwmf-dev libx11-dev libxt-dev libxext-dev libxml2-dev libfreetype6-dev liblcms1-dev libexif-dev perl libjasper-dev libltdl3-dev graphviz gs-gpl pkg-config

log "Installing RVM system-wide"
curl -L get.rvm.io | sudo bash -s stable
usermod -a -G rvm "$DEPLOY_USER"

source /etc/profile.d/rvm.sh
source /etc/profile

log "Installing Ruby $RUBY_RELEASE"
rvm install $RUBY_RELEASE
rvm use $RUBY_RELEASE --default

log "Updating Ruby gems"
set_production_gemrc
gem update --system


log "Instaling Phusion Passenger and Nginx"
gem install passenger
rvmsudo passenger-install-nginx-module --auto --auto-download --prefix="/usr/local/nginx"

log "Setting up Nginx to start on boot and rotate logs"
set_nginx_boot_up

log "Setting Rails/Rack defaults"
set_default_environment

log "Install Bundler"
gem install bundler

log "Update SSH port"
update_ssh_port

log "Install imagemagick"
system_install_imagemagick

log "Restarting Services"
restartServices

