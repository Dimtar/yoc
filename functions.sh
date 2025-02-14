#!/bin/bash

check_os_installed () {
#Check if a supported distribution is installed
OS_VERSION=$(. /etc/os-release && echo "$VERSION_CODENAME")
case "$OS_VERSION" in
   bookworm|bullseye|lunar|kinetic|jammy|focal)
                 echo "You are running a supported version"
                 ;; # and exit the case
   *)            echo "You are running an unsupported version"
                exit 0
                ;;
esac
}
check_whiptail_is_installed () {
WHIPTAIL_BIN=$(which whiptail)

    if [ -z "$WHIPTAIL_BIN" ]; then
        echo "whiptail installation for a nice looking UI"
        apt update
        apt install whiptail -y 
    fi
}

whiptail_cancel_escape () {
if [[ $? != 0 ]] ; then
  exit 0
fi
}

##Check if docker is installed
check_if_docker_installed () {
DOCKER_BIN=$(which docker)
    if [ -z "$DOCKER_BIN" ]
    then
        whiptail --title "YOC Installation" --yesno "Docker is not installed, do you want to install it?" 8 78 
        if [[ $? -eq 0 ]]; then
          install_docker
        elif [[ $? -eq 1 ]]; then 
          whiptail --title "YOC Installation" --msgbox "You can install docker manually and restart the install script." 8 78 
          exit 0
        elif [[ $? -eq 255 ]]; then 
          whiptail --title "YOC Installation" --msgbox "User pressed ESC. Exiting the script" 8 78 
          exit 0
        fi 
    else
        whiptail --title "YOC Installation" --msgbox "Docker is already installed" 8 78
        whiptail_cancel_escape
    fi
}

install_docker () {
OS_ID=$(. /etc/os-release && echo "$ID")
    apt update
    apt upgrade -y
    apt install ca-certificates curl gnupg -y
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$OS_ID/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
    "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS_ID \
    "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt update
    apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
}

check_if_docker_working () {
echo "Check if docker is working"
DOCKER_CHECK=$(docker run hello-world | grep "Hello from Docker")
    if [ -z "$DOCKER_CHECK" ]
    then
        whiptail --title "YOC Installation" --msgbox "Docker is not working, restart the server to see if it fix the problem." 8 78
        whiptail_cancel_escape
    else
        whiptail --title "YOC Installation" --msgbox "Docker is up and running." 8 78 
        whiptail_cancel_escape
    fi
}

create_domains_list () {
#Create list of DNS Entries
if [[ $VAULTWARDEN == 1 ]]; then
  echo "vaultwarden.$DOMAIN_NAME" >> dns.list
fi

if [[ $SEAFILE == 1 ]]; then
  echo "seafile.$DOMAIN_NAME" >> dns.list
fi
  
if [[ $NEXTCLOUD == 1 ]]; then
  echo "nextcloud.$DOMAIN_NAME" >> dns.list
fi

if [[ $WG_EASY == 1 ]]; then
  echo "vpn.$DOMAIN_NAME" >> dns.list
fi

if [[ $IMMICH == 1 ]]; then
  echo "immich.$DOMAIN_NAME" >> dns.list
fi
}

#Ceate DNS entries in CLoudflare DNS
create_cloudflare_dns_entries () {
#GET DNS Zone from Cloudflare
#Check if jq is installed
JQ_BIN=$(which jq)
if [ -z "$JQ_BIN" ]
  then
  echo "jq installation to work with APIs"
  apt update
  apt install jq -y 
fi

CLOUDFLARE_DNS_ZONE=$( curl -s --request GET --url https://api.cloudflare.com/client/v4/zones --header 'Content-Type: application/json' --header 'Authorization: Bearer '$CLOUDFLARE_API_KEY'' | jq -r '.result[].id')
while read line;
do
  ##Check if the DNS Entrie already exist
  CHECK_RECORD_ALREADY_EXIST=$(curl -s --request GET \
  --url https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_DNS_ZONE/dns_records \
  --header 'Content-Type: application/json' \
  --header 'Authorization: Bearer '$CLOUDFLARE_API_KEY'' | grep $line)
  
   if [ -z "$CHECK_RECORD_ALREADY_EXIST" ]
    then
      echo "$line does not exist"
      curl --request POST \
      --url https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_DNS_ZONE/dns_records \
      --header 'Content-Type: application/json' \
      --header 'Authorization: Bearer '$CLOUDFLARE_API_KEY'' \
      --data '{
      "content": "'$PUBLIC_IP'",
      "name": "'$line'",
      "proxied": true,
      "type": "A",
      "comment": "A Record for '$line'"
      }'
    else
      echo "$line exist"
  fi
done < dns.list
}

install_wg_easy_or_adguardghome () {
    DNS_ENTRIES=$(cat dns.list)
    if [[ $WG_EASY != 1 ]]; then
        WG_EASY=1
        whiptail --title "YOC Installation" --yesno "Do you want to install Wireguard VPN to access remotely?" 8 78
        if [[ $? -eq 0 ]]; then
            WG_EASY=1
        elif [[ $? -eq 1 ]]; then 
            WG_EASY=0
        elif [[ $? -eq 255 ]]; then 
          exit 0
        fi
    fi  
    if [[ $ADGUARDHOME != 1 ]]; then
        ADGUARDHOME=1
        whiptail --title "YOC Installation" --yesno "Do you want to install Adguardhome to act as a local DNS Server?\nIt will create the rewrites rules for:\n$DNS_ENTRIES\nto $SERVER_IP." 20 78  
        if [[ $? -eq 0 ]]; then
        ADGUARDHOME=1
        elif [[ $? -eq 1 ]]; then
            ADGUARDHOME=0
        elif [[ $? -eq 255 ]]; then
          exit 0
        fi
    fi
}

configure_cloudflare () {
    DOMAIN_NAME=$(whiptail --title="YOC Installation" --inputbox "Which domain name you want to use?" 8 78 3>&1 1>&2 2>&3)
    whiptail_cancel_escape
        while true
            do
                CLOUDFLARE_API_KEY=$(whiptail --title="YOC Installation" --passwordbox "Cloudflare API Key?\n(For Traefik DNS challenge)" 8 78 3>&1 1>&2 2>&3)
                whiptail_cancel_escape
                CHECK_CLOUDFLARE_API_KEY=$(curl -s "https://api.cloudflare.com/client/v4/user/tokens/verify" --header "Authorization: Bearer $CLOUDFLARE_API_KEY" | grep "This API Token is valid and active")
                    if [ -z "$CHECK_CLOUDFLARE_API_KEY" ]; then
                        whiptail --title "YOC Installation" --msgbox "CloudFlare API Key Not valid, try again" 8 78
                        whiptail_cancel_escape
                        continue
                    else
                        whiptail --title "YOC Installation" --msgbox "CloudFlare API Key Valid" 8 78
                        whiptail_cancel_escape
                        break
                    fi
            done

create_domains_list

PUBLIC_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)
DNS_ENTRIES=$(cat dns.list)
whiptail --title "YOC Installation" --yesno "Do you want to expose your services to internet? \nIf yes the followings DNS entries will be created:\n\n$DNS_ENTRIES\n\nTo your public IP $PUBLIC_IP on Cloudflare." 20 78
if [[ $? -eq 0 ]]; then
  #Create the DNS entries
  create_cloudflare_dns_entries
  whiptail --title "YOC Installation" --msgbox "You can open the ports 443 on your router/firewall to the server IP $SERVER_IP" 8 78
  whiptail_cancel_escape
elif [[ $? -eq 1 ]]; then
    install_wg_easy_or_adguardghome
elif [[ $? -eq 255 ]]; then
    exit 0
fi
}