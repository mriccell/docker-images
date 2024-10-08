#!/bin/bash
# LICENSE UPL 1.0
#
# Copyright (c) 2022  Oracle and/or its affiliates.
#
# Since: January, 2018
# Author: paramdeep.saini@oracle.com
# Description: Configure and setup CMAN 
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

source /tmp/envfile

source $SCRIPT_DIR/functions.sh 

####################### Constants #################
# shellcheck disable=SC2034
declare -r FALSE=1
# shellcheck disable=SC2034
declare -r TRUE=0
# shellcheck disable=SC2034
declare -r ETCHOSTS="/etc/hosts"
# shellcheck disable=SC2034
progname="$(basename $0)"
###################### Constants ####################

WALLET_TMPL_STR='wallet_location = 
	(source=
		(method=File)
		(method_data=
			(directory=###WALLET_LOCATION###)
	  	)
	)
SQLNET.WALLET_OVERRIDE = TRUE'

RULESRCSET=0
RULEDSTSET=0
RULESRVSET=0
CP="/bin/cp"

all_check()
{
check_env_vars
}

check_env_vars ()
{
## Checking Grid Reponsfile or vip,scan ip and private ip
### if user has passed the Grid ResponseFile name, below checks will be skipped

# Following checks will be executed if user is not providing Grid Response File

if [ -z "${DOMAIN}" ]; then
   print_message  "Domain name is not defined. Setting Domain to 'example.com'"
   DOMAIN="example.com"
 else
 print_message "Domain is defined to $DOMAIN"
fi

if [ -z "${PORT}" ]; then
   print_message  "PORT is not defined. Setting PORT to '1521'"
   PORT="1521"
 else
 print_message "PORT is defined to $PORT"
fi

if [ -z "${PUBLIC_IP}" ]; then
    error_exit  "Container hostname is not set or set to the empty string"
else
    print_message "Public IP is set to ${PUBLIC_IP}"
fi

if [ -z "${PUBLIC_HOSTNAME}" ]; then
   error_exit "RAC Node PUBLIC Hostname is not set ot set to empty string"
else
  print_message "RAC Node PUBLIC Hostname is set to ${PUBLIC_HOSTNAME}"
fi

if [ -z ${SCAN_NAME} ]; then
  print_message "SCAN_NAME set to the empty string"
else
  print_message "SCAN_NAME name is ${SCAN_NAME}"
fi

if [ -z ${SCAN_IP} ]; then
   print_message "SCAN_IP set to the empty string"
else
  print_message "SCAN_IP name is ${SCAN_IP}"
fi

if [ -z "${LOG_LEVEL}" ]; then
   LOG_LEVEL=user
fi

if [ -z "${TRACE_LEVEL}" ]; then
   TRACE_LEVEL=user
fi

if [ -z "${RULE_SRC}" ]; then
   RULE_SRC='*'
else
   RULESRCSET=1
fi

if [ -z "${RULE_DST}" ]; then
   RULE_DST='*'
else
   RULEDSTSET=1
fi

if [ -z "${RULE_SRV}" ]; then
   RULE_SRV='*'
else
   RULESRVSET=1
fi

if [ -z "${RULE_ACT}" ]; then
   RULE_ACT='accept'
fi

if [ -z "${REGISTRATION_INVITED_NODES}" ]; then
   REGISTRATION_INVITED_NODES='*'
else
# shellcheck disable=SC2034
   REGINVITEDNODESET=1
fi
# shellcheck disable=SC2166
if [ "${TRACE_LEVEL}" != "user" -a "${TRACE_LEVEL}" != "admin" -a "${TRACE_LEVEL}" != "support" ]; then
      print_message "Invalid trace-level [${TRACE_LEVEL}] specified."
fi
# shellcheck disable=SC2166
if [ "${LOG_LEVEL}" != "user" -a "${LOG_LEVEL}" != "admin" -a "${LOG_LEVEL}" != "support" ]; then
      print_message "Invalid log-level [${LOG_LEVEL}] specified."
fi

contSubNetIP=`/sbin/ifconfig eth0 | grep 'inet ' | awk '{ print $2 }' | awk -F. '{ print $1 "." $2 "." $3 }'`
echo "Subnet=[$contSubNetIP]"

if [ $RULESRCSET -eq 1 ]; then
   echo ${RULE_SRC} | grep $contSubNetIP > /dev/null 2>&1

   if [ $? -ne 0 ]; then
      print_message "Invalid input. SourceIP [${RULE_SRC}] not a valid subnet. "
   fi
fi

if [ $RULEDSTSET -eq 1 ]; then
   echo ${RULE_DST} | grep $contSubNetIP > /dev/null 2>&1

   if [ $? -ne 0 ]; then
      print_message "Invalid input. DestinationIP [${RULE_DST}] not a valid subnet. "
   fi
fi

if [ $RULESRVSET -eq 1 ]; then
   echo ${RULE_SRV} | grep $contSubNetIP > /dev/null 2>&1

   if [ $? -ne 0 ]; then
      print_message "Invalid input. SrvIP [${RULE_SRV}] not a valid subnet. "
   fi
fi
# shellcheck disable=SC2166
if [ "${RULE_ACT}" != "accept" -a "${RULE_ACT}" != "reject" -a "${RULE_ACT}" != "drop" ]; then
      print_message "Invalid rule-action [${RULE_ACT}] specified."
fi

}

####################################### ETC Host Function #############################################################

SetupEtcHosts()
{
# shellcheck disable=SC2034
stat=3
# shellcheck disable=SC2034
local HOST_LINE

echo -e "127.0.0.1\tlocalhost.localdomain\tlocalhost" > /etc/hosts
echo -e "$PUBLIC_IP\t$PUBLIC_HOSTNAME.$DOMAIN\t$PUBLIC_HOSTNAME" >> /etc/hosts
echo -e "$SCAN_IP\t$SCAN_NAME.$DOMAIN\t$SCAN_NAME" >> /etc/hosts
}

######### Grid setup Function###########################
cman_file ()
{

cp $SCRIPT_DIR/$CMANORA $logdir/$CMANORA

sed -i -e "s|###CMAN_HOSTNAME###|$PUBLIC_HOSTNAME|g" $logdir/$CMANORA
sed -i -e "s|###DOMAIN###|$DOMAIN|g" $logdir/$CMANORA
sed -i -e "s|###DB_HOME###|$DB_HOME|g" $logdir/$CMANORA
sed -i -e "s|###PORT###|$PORT|g" $logdir/$CMANORA
sed -i -e "s|###LOG_LEVEL###|$LOG_LEVEL|g" $logdir/$CMANORA
sed -i -e "s|###TRACE_LEVEL###|$TRACE_LEVEL|g" $logdir/$CMANORA
sed -i -e "s|(registration_invited_nodes=.*)|(registration_invited_nodes=${REGISTRATION_INVITED_NODES})|g"  $logdir/$CMANORA
sed -i -e "s|(src=.*)|(src=${RULE_SRC})(dst=${RULE_DST})(srv=${RULE_SRV})(act=${RULE_ACT})|g"  $logdir/$CMANORA

if [ ! -z "${WALLET_LOCATION}" ]; then
   echo "$WALLET_TMPL_STR" >> $logdir/$CMANORA
   sed -i -e "s|###WALLET_LOCATION###|${WALLET_LOCATION}|g" $logdir/$CMANORA
fi

}

copycmanora ()
{
mkdir -p $DB_HOME/network/admin/
sleep 2
cp $logdir/$CMANORA $DB_HOME/network/admin/
chown -R oracle:oinstall $DB_HOME/network/admin/
#rm -f $logdir/$CMANORA
}

start_cman ()
{
local cmd
cmd="su - oracle -c \"$DB_HOME/bin/cmctl startup -c CMAN_$PUBLIC_HOSTNAME.$DOMAIN\""
eval $cmd
}

stop_cman ()
{
local cmd
cmd="su - oracle -c \"$DB_HOME/bin/cmctl shutdown -c CMAN_$PUBLIC_HOSTNAME.$DOMAIN\""
eval $cmd
}

status_cman ()
{
local cmd
cmd="su - oracle -c \"$DB_HOME/bin/cmctl show service -c CMAN_$PUBLIC_HOSTNAME.$DOMAIN\""
eval $cmd

if [ $? -eq 0 ];then
print_message "cman started sucessfully"
else
   if [ -z "${CMAN_DEBUG}" ]; then
      error_exit "Cman startup failed. Exiting"
   else
      print_message "Cman startup failed. Debug mode"
      tail -f /tmp/orod.log

   fi
fi

}


###################################
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! #
############# MAIN ################
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! #
###################################

########
#clear_files
SetupEtcHosts
if [ ! -z "${USER_CMAN_FILE}" ]; then
   if [ ! -f "${USER_CMAN_FILE}" ]; then
        error_exit "User supplied cman.ora file [${USER_CMAN_FILE}] not found. Exiting CMAN-Setup."
   else
        print_message "Using the user defined cman.ora file=[${USER_CMAN_FILE}]"
        ${CP} ${USER_CMAN_FILE} $logdir/$CMANORA
   fi
else
   all_check
   print_message "Generating CMAN file"
   cman_file
fi

print_message "Copying CMAN file to $DB_HOME/network/admin"
copycmanora
print_message "Starting CMAN"
start_cman
print_message "Checking CMAN Status"
status_cman
print_message "################################################"
print_message " CONNECTION MANAGER IS READY TO USE!            "
print_message "################################################"
