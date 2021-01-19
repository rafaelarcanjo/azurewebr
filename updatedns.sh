#!/bin/sh

# *********************************************************************
# Adaptado por Rafael Arcanjo <rafael.wzs@gmail.com>
# Adaptação inicial: 2020-09-15
#
# Script para atualizar o registro DNS 
#
# Adaptado para Jefferson T @azurewebr
# Portal Freelancer.com
# *********************************************************************

# Copyright 2018 cPanel, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#
# Constantes originais
#
CONTACT_EMAIL="admin@admin.com"
DOMAIN=""
SUBDOMAIN=""
CPANEL_SERVER=""
CPANEL_USER=""
CPANEL_PASS=""
QUIET="1"

#
# Minhas constantes
#
FILE_IPS="/usr/local/updatedns/ips"     # Arquivo onde estao os IPS
WAITING="0s"                            # tempo para aguardar... ex: 1s = um segundo / 1m = um minuto / 1h = uma hora

#
# Funcoes originais
#
banner ()
{
    if [ "$QUIET" != "1" ]; then
        echo "=="
        echo "== cPanel Dyanmic DNS Updater $VERSION"
        echo "=="
        echo "==  Updating domain $FULL_DOMAIN"
        echo "=="
        echo $CFGMESSAGE1
        echo $CFGMESSAGE2
        echo "=="
    fi
}

exit_timeout ()
{
    ALARMPID=""
    say "The operation timed out while connecting to %s\n" "$LAST_CONNECT_HOST"
    notify_failure "Timeout" "Connection Timeout" "Timeout while connecting to $LAST_CONNECT_HOST"
    exit
}

setup_vars ()
{

    VERSION="2.1"
    APINAME=""
    PARENTPID=$$
    HOMEDIR=`echo ~`
    LAST_CONNECT_HOST=""
    FAILURE_NOTIFY_INTERVAL="14400"
    PERMIT_ROOT_EXECUTION="0"
    NOTIFY_FAILURE="1"
    TIMEOUT="120"
    BASEDIR="cpdyndns"

    # Find a suitable path for perl.
    PATH="/usr/local/cpanel/3rdparty/bin:$PATH:/usr/bin:/usr/local/bin"
}

setup_config_vars ()
{

    if [ "$SUBDOMAIN" = "" ]; then
        APINAME="$DOMAIN."
    else
        APINAME="$SUBDOMAIN"
        SUBDOMAIN="$SUBDOMAIN"
    fi
    LAST_RUN_FILE="$HOMEDIR/.$BASEDIR/$FULL_DOMAIN.lastrun"
    LAST_FAIL_FILE="$HOMEDIR/.$BASEDIR/$FULL_DOMAIN.lastfail"
}

load_config ()
{
    if [ -e "/etc/$BASEDIR.conf" ]; then
        chmod 0600 /etc/$BASEDIR.conf
        . /etc/$BASEDIR.conf
        CFGMESSAGE1="== /etc/$BASEDIR.conf is being used for configuration"
    else
        CFGMESSAGE1="== /etc/$BASEDIR.conf does not exist"
    fi
    if [ -e "$HOMEDIR/etc/$BASEDIR.conf" ]; then
        chmod 0600 $HOMEDIR/etc/$BASEDIR.conf
        . $HOMEDIR/etc/$BASEDIR.conf
        CFGMESSAGE2="== $HOMEDIR/etc/$BASEDIR.conf is being used for configuration"
    else
        CFGMESSAGE2="== $HOMEDIR/etc/$BASEDIR.conf does not exist"
    fi
}

create_dirs ()
{
    if [ ! -e "$HOMEDIR/.$BASEDIR" ]; then
        mkdir -p "$HOMEDIR/.$BASEDIR"
        chmod 0700 "$HOMEDIR/.$BASEDIR"
    fi
}

say ()
{
    [ "$QUIET" = "1" ] && return
    printf "$@"
}

fetch_myaddress ()
{
    MYADDRESS=$1

    say "%s...Done\n" "$MYADDRESS"
    if [ "$MYADDRESS" = "" ]; then
        say "Failed to determine IP Address (via https://www.cpanel.net/myip/)\n"
    fi
    return
}

load_last_run ()
{
    if [ -e "$LAST_RUN_FILE" ]; then
        . $LAST_RUN_FILE
    fi
}

exit_if_last_address_is_current ()
{
    if [ "$LAST_ADDRESS" = "$MYADDRESS" ]; then
        say "Last update was for %s, and address has not changed.\n" "$LAST_ADDRESS"
        say "If you want to force an update, remove %s\n" "$LAST_RUN_FILE"
    fi
}

generate_auth_string () {
    AUTH_STRING=`printf "%s:%s" "$CPANEL_USER" "$CPANEL_PASS" | openssl enc -base64`
}

fetch_zone () {
    say "Fetching zone for %s...." "$DOMAIN"
    LAST_CONNECT_HOST=$CPANEL_SERVER
    REQUEST="GET /json-api/cpanel?cpanel_jsonapi_module=ZoneEdit&cpanel_jsonapi_func=fetchzone&cpanel_jsonapi_apiversion=2&domain=$DOMAIN HTTP/1.0\r\nConnection: close\r\nAuthorization: Basic $AUTH_STRING\r\nUser-Agent: cpanel-dynamic-dns $VERSION\r\n\r\n\r\n"
    RECORD=""
    LINES=""
    INRECORD=0
    USETHISRECORD=0
    REQUEST_RESULTS=`printf "$REQUEST" | openssl s_client -quiet -connect $CPANEL_SERVER:2083 2>/dev/null`

    check_results_for_error "$REQUEST_RESULTS" "$REQUEST"    

    LINES="$(extract_from_json "$REQUEST_RESULTS" "
        do {
            join(qq{\n}, map {
                qq{\$_->{Line}=\$_->{address}}
            } grep {
                \$_->{type} eq q{A} && \$_->{name} eq q{$FULL_DOMAIN.}
            } @{\$_->{cpanelresult}{data}[0]{record}});
        }
    ")"

    say "Done\n"
}

parse_zone () {
    say "Looking for duplicate entries..."
    FIRSTLINE=""
    REVERSELINES=""
    DUPECOUNT=0
    for LINE in `printf "$LINES"`
    do
        if [ "$LINE" = "" ]; then
            continue
        fi
        if [ "$FIRSTLINE" = "" ]; then
            FIRSTLINE=$LINE
            continue
        fi

        DUPECOUNT=`expr $DUPECOUNT + 1`
        REVERSELINES="$LINE\n$REVERSELINES"
    done

    say "Found %d duplicates\n" "$DUPECOUNT"
    for LINE in `printf "$REVERSELINES"`
    do
        if [ "$LINE" = "" ]; then
            continue
        fi
        LINENUM=`echo $LINE | awk -F= '{print $1}'`
        LAST_CONNECT_HOST=$CPANEL_SERVER
        REQUEST="GET /json-api/cpanel?cpanel_jsonapi_module=ZoneEdit&cpanel_jsonapi_func=remove_zone_record&cpanel_jsonapi_apiversion=2&domain=$DOMAIN&line=$LINENUM HTTP/1.0\r\nConnection: close\r\nAuthorization: Basic $AUTH_STRING\r\nUser-Agent: cpanel-dynamic-dns $VERSION\r\n\r\n\r\n"
        say "Removing Duplicate entry for %s%s. (line %d)\n" "$SUBDOMAIN" "$DOMAIN" "$LINENUM"
        RESULT=`printf "$REQUEST" | openssl s_client -quiet -connect $CPANEL_SERVER:2083 2>&1`
        check_results_for_error "$RESULT" "$REQUEST"
        say "%s\n" "$RESULT"
    done
}

update_records () {

    if [ "$FIRSTLINE" = "" ]; then
        say "Record %s%s. does not exist.  Setting %s%s. to %s\n" "$SUBDOMAIN" "$DOMAIN" "$SUBDOMAIN" "$DOMAIN" "$MYADDRESS"
        LAST_CONNECT_HOST=$CPANEL_SERVER
        REQUEST="GET /json-api/cpanel?cpanel_jsonapi_module=ZoneEdit&cpanel_jsonapi_func=add_zone_record&cpanel_jsonapi_apiversion=2&domain=$DOMAIN&name=$APINAME&type=A&address=$MYADDRESS&ttl=1 HTTP/1.0\r\nConnection: close\r\nAuthorization: Basic $AUTH_STRING\r\nUser-Agent: cpanel-dynamic-dns $VERSION\r\n\r\n\r\n"
        RESULT=`printf "$REQUEST" | openssl s_client -quiet -connect $CPANEL_SERVER:2083 2>&1`
        check_results_for_error "$RESULT" "$REQUEST"
    else
        ADDRESS=`echo $FIRSTLINE | awk -F= '{print $2}'`
        LINENUM=`echo $FIRSTLINE | awk -F= '{print $1}'`

        if [ "$ADDRESS" = "$MYADDRESS" ]; then
            say "Record %s%s. already exists in zone on line %s of the %s zone.\n" "$SUBDOMAIN" "$DOMAIN" "$LINENUM" "$DOMAIN"
            say "Not updating as its already set to %s\n" "$ADDRESS"
            echo "LAST_ADDRESS=\"$MYADDRESS\"" > $LAST_RUN_FILE
        fi
        say "Record %s%s. already exists in zone on line %d with address %s.   Updating to %s\n" "$SUBDOMAIN" "$DOMAIN" "$LINENUM" "$ADDRESS" "$MYADDRESS"
        LAST_CONNECT_HOST=$CPANEL_SERVER
        REQUEST="GET /json-api/cpanel?cpanel_jsonapi_module=ZoneEdit&cpanel_jsonapi_func=edit_zone_record&cpanel_jsonapi_apiversion=2&Line=$FIRSTLINE&domain=$DOMAIN&name=$APINAME&type=A&address=$MYADDRESS&ttl=1 HTTP/1.0\r\nConnection: close\r\nAuthorization: Basic $AUTH_STRING\r\nUser-Agent: cpanel-dynamic-dns $VERSION\r\n\r\n\r\n"
        RESULT=`printf "$REQUEST" | openssl s_client -quiet -connect $CPANEL_SERVER:2083 2>&1`
        check_results_for_error "$RESULT" "$REQUEST"
    fi


    if [ "`echo $RESULT | grep newserial`" ]; then
        say "Record updated ok\n"
        echo "LAST_ADDRESS=\"$MYADDRESS\""  > $LAST_RUN_FILE
    else
        say "Failed to update record\n"
        say "%s\n" "$RESULT"
    fi

}

extract_from_json ()
{
    DATA="$1"
    PATTERN="$2"

    printf "%s" "$DATA" | \
        perl -0777 -MJSON::PP -p \
        -e '(undef, $_) = split /\r\n\r\n/, $_, 2;' \
        -e '$_ = JSON::PP::decode_json($_);' \
        -e "\$_ = $PATTERN;"
}

check_results_for_error ()
{
    RESULTS="$1"
    REQUEST="$2"
    if [ "$(extract_from_json "$RESULTS" '$_->{cpanelresult}{event}{result}')" = "1" ]; then
        say "success..."
    else
        INREASON=0
        INSTATUSMSG=0
        MSG=""
        STATUSMSG=""

        MSG="$(extract_from_json "$RESULTS" 'ref $_->{cpanelresult}{data} eq q{ARRAY} ? $_->{cpanelresult}{data}[0]{reason} : $_->{cpanelresult}{data}{reason}')"
        STATUSMSG="$(extract_from_json "$RESULTS" 'ref $_->{cpanelresult}{data} eq {ARRAY} ? $_->{cpanelresult}{data}[0]{statusmsg} : $_->{cpanelresult}{data}{statusmsg}')"

        if [ "$MSG" = "" ]; then
            MSG="Unknown Error"
            if [ "$STATUSMSG" = "" ]; then
                STATUSMSG="Please make sure you have the zoneedit, or simplezone edit permission on your account."
            fi
        fi
        say "Request failed with error: %s (%s)\n" "$MSG" "$STATUSMSG"
        notify_failure "$MSG" "$STATUSMSG" "$REQUEST_RESULTS" "$REQUEST"
    fi
}

notify_failure ()
{
    MSG="$1"
    STATUSMSG="$2"
    REQUEST_RESULTS="$3"
    CURRENT_TIME=`date +%s`
    LAST_TIME=0
    if [ -e "$LAST_FAIL_FILE" ]; then
        . $LAST_FAIL_FILE
    fi
    TIME_DIFF=`expr $CURRENT_TIME - $LAST_TIME`

    if [ "$CONTACT_EMAIL" = "" ]; then
        echo "No contact email address was set.  Cannot send failure notification."
        return
    fi

    if [ $TIME_DIFF -gt $FAILURE_NOTIFY_INTERVAL ]; then
        echo "LAST_TIME=$CURRENT_TIME" > $LAST_FAIL_FILE

        SUBJECT="Failed to update dynamic DNS for $FULL_DOMAIN. on $CPANEL_SERVER : $MSG ($STATUMSG)"
        if [ -e "/bin/mail" ]; then
            say "sending email notification of failure.\n"
            printf "Status Message: $STATUSMSG\nThe full response was: $REQUEST_RESULTS" | /bin/mail -s "$SUBJECT" $CONTACT_EMAIL
        else
            say "/bin/mail is not available, cannot send notification of failure.\n"
        fi
    else
        say "skipping notification because a notication was sent %d seconds ago.\n" "$TIME_DIFF"
    fi
}

check_config () {
    if [ "$CONTACT_EMAIL" = "" ]; then
        echo "= Warning: no email address set for notifications"
    fi
    if [ "$CPANEL_SERVER" = "" ]; then
        echo "= Error: CPANEL_SERVER must be set in a configuration file"
        exit
    fi
    if [ "$DOMAIN" = "" ]; then
        echo "= Error: DOMAIN must be set in a configuration file"
        exit
    fi
    if [ "$CPANEL_USER" = "" ]; then
        echo "= Error: CPANEL_USER must be set in a configuration file"
        exit
    fi
    if [ "$CPANEL_PASS" = "" ]; then
        echo "= Error: CPANEL_PASS must be set in a configuration file"
        exit
    fi
    if ! perl -MJSON::PP -e1 >/dev/null 2>&1; then
        echo "= Error: A version of perl with JSON::PP must be in the PATH"
        exit
    fi
}

#
# Minhas funcoes
#
updateIp() {
    setup_vars
    load_config
    setup_config_vars
    banner
    check_config
    fetch_myaddress $1
    create_dirs
    load_last_run
    exit_if_last_address_is_current
    generate_auth_string
    fetch_zone
    parse_zone
    update_records
    restartDNS
}

restartDNS() {
    systemctl restart pdns.service
}

#updateIp 1.1.1.1
# Loop infinito
while : ; do
    # Setando a variável
    if [ -z "$SUBDOMAIN" ]; then
        FULL_DOMAIN=$DOMAIN
    else
        FULL_DOMAIN="$SUBDOMAIN.$DOMAIN"
    fi
    
    # Verificando se o server esta online
    ping=$(ping -W 1 -c 1 $FULL_DOMAIN | grep ttl)

    if [ -z "$ping" ]; then
        echo "SERVER: $FULL_DOMAIN is DOWN... Checking the ips"

        for i in $(cat $FILE_IPS); do
            ping=$(ping -W 1 -c 1 $i | grep ttl)

            if [ -z "$ping" ]; then
                echo "IP: $i is DOWN... Check the next"
            else
                echo "IP: $i is up... Updating"
                updateIp $i
                break
            fi
	    done
    #else
        #echo "SERVER: $FULL_DOMAIN online... Nothing to do"
    fi	

	# Aguardando
	#echo "Waiting $WAITING"
	sleep $WAITING
done
