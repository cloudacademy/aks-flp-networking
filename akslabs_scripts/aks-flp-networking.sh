#!/bin/bash

# script name: aks-flp-networking.sh
# Version v0.0.2 20211008
# Set of tools to deploy AKS troubleshooting labs

# "-l|--lab" Lab scenario to deploy (5 possible options)
# "-r|--region" region to deploy the resources
# "-u|--user" User alias to add on the lab name
# "-h|--help" help info
# "--version" print version

# read the options
TEMP=`getopt -o g:n:l:r:u:hv --long resource-group:,name:,lab:,region:,user:,help,validate,version -n 'aks-flp-networking.sh' -- "$@"`
eval set -- "$TEMP"

# set an initial value for the flags
RESOURCE_GROUP=""
CLUSTER_NAME=""
LAB_SCENARIO=""
USER_ALIAS=""
LOCATION="eastus2"
VALIDATE=0
HELP=0
VERSION=0

while true ;
do
    case "$1" in
        -h|--help) HELP=1; shift;;
        -g|--resource-group) case "$2" in
            "") shift 2;;
            *) RESOURCE_GROUP="$2"; shift 2;;
            esac;;
        -n|--name) case "$2" in
            "") shift 2;;
            *) CLUSTER_NAME="$2"; shift 2;;
            esac;;
        -l|--lab) case "$2" in
            "") shift 2;;
            *) LAB_SCENARIO="$2"; shift 2;;
            esac;;
        -r|--region) case "$2" in
            "") shift 2;;
            *) LOCATION="$2"; shift 2;;
            esac;;
        -u|--user) case "$2" in
            "") shift 2;;
            *) USER_ALIAS="$2"; shift 2;;
            esac;;    
        -v|--validate) VALIDATE=1; shift;;
        --version) VERSION=1; shift;;
        --) shift ; break ;;
        *) echo -e "Error: invalid argument\n" ; exit 3 ;;
    esac
done

# Variable definition
SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
SCRIPT_NAME="$(echo $0 | sed 's|\.\/||g')"
SCRIPT_VERSION="Version v0.0.2 20211008"

# Funtion definition

# az login check
function az_login_check () {
    if $(az account list 2>&1 | grep -q 'az login')
    then
        echo -e "\n--> Error: You have to login first with the 'az login' command before you can run this lab tool\n"
        az login -o table
    fi
}

# check resource group and cluster
function check_resourcegroup_cluster () {
    RESOURCE_GROUP="$1"
    CLUSTER_NAME="$2"

    RG_EXIST=$(az group show -g $RESOURCE_GROUP &>/dev/null; echo $?)
    if [ $RG_EXIST -ne 0 ]
    then
        echo -e "\n--> Creating resource group ${RESOURCE_GROUP}...\n"
        az group create --name $RESOURCE_GROUP --location $LOCATION &>/dev/null
    else
        echo -e "\nResource group $RESOURCE_GROUP already exists...\n"
    fi

    CLUSTER_EXIST=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME &>/dev/null; echo $?)
    if [ $CLUSTER_EXIST -eq 0 ]
    then
        echo -e "\n--> Cluster $CLUSTER_NAME already exists...\n"
        echo -e "Please remove that one before you can proceed with the lab.\n"
        exit 5
    fi
}

# validate cluster exists
function validate_cluster_exists () {
    RESOURCE_GROUP="$1"
    CLUSTER_NAME="$2"

    CLUSTER_EXIST=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME &>/dev/null; echo $?)
    if [ $CLUSTER_EXIST -ne 0 ]
    then
        echo -e "\n--> ERROR: Failed to create cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP ...\n"
        exit 5
    fi
}

# Lab scenario 1
function lab_scenario_1 () {
    CLUSTER_NAME=aks-net-ex1-${USER_ALIAS}
    RESOURCE_GROUP=aks-net-ex1-rg-${USER_ALIAS}
    check_resourcegroup_cluster $RESOURCE_GROUP $CLUSTER_NAME
    VNET_NAME=aks-vnet-ex1
    SUBNET_NAME=aks-subnet-ex1
    UDR_NAME=security-routes

    echo -e "--> Deploying cluster for lab1...\n"
    az network vnet create \
    --resource-group $RESOURCE_GROUP \
    --name $VNET_NAME \
    --address-prefixes 192.168.0.0/16 \
    --subnet-name $SUBNET_NAME \
    --subnet-prefix 192.168.100.0/24 \
    -o table
	
    SUBNET_ID=$(az network vnet subnet list \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --query [].id --output tsv)

    az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --location $LOCATION \
    --node-count 2 \
    --network-plugin kubenet \
    --service-cidr 10.0.0.0/16 \
    --dns-service-ip 10.0.0.10 \
    --docker-bridge-address 172.17.0.1/16 \
    --vnet-subnet-id $SUBNET_ID \
    --tag aks-net-lab=${LAB_SCENARIO} \
    --generate-ssh-keys \
    --yes \
    -o table

    validate_cluster_exists $RESOURCE_GROUP $CLUSTER_NAME

    echo -e "\n\n--> Please wait while we are preparing the environment for you to troubleshoot..."
    az network route-table create -g $RESOURCE_GROUP --name $UDR_NAME -o table
    az network vnet subnet update -g $RESOURCE_GROUP -n $SUBNET_NAME --vnet-name $VNET_NAME --route-table $UDR_NAME -o table
    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"
    echo -e "\n************************************************************************\n"
    echo -e "Case 1 is ready, pods on different nodes not able to talk to each other...\n"
    echo -e "Cluster uri == ${CLUSTER_URI}\n"
}

function lab_scenario_1_validation () {
    CLUSTER_NAME=aks-net-ex1-${USER_ALIAS}
    RESOURCE_GROUP=aks-net-ex1-rg-${USER_ALIAS}
    VNET_NAME=aks-vnet-ex1
    SUBNET_NAME=aks-subnet-ex1
    LAB_TAG="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query tags -o tsv 2>/dev/null)"
    echo -e "\n+++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo -e "--> Running validation for Lab scenario $LAB_SCENARIO\n"
    if [ -z $LAB_TAG ]
    then
        echo -e "\n--> Error: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    elif [ $LAB_TAG -eq $LAB_SCENARIO ]
    then
        az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null
        CLUSTER_RESOURCE_GROUP=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query nodeResourceGroup -o tsv)
        CLUSTER_UDR="$(az network route-table list -g $CLUSTER_RESOURCE_GROUP --query [].name -o tsv)"
        CURRENT_UDR="$(az network vnet subnet show -g $RESOURCE_GROUP -n $SUBNET_NAME --vnet-name $VNET_NAME --query routeTable.id -o tsv | awk -F'/' '{print $NF}' 2>/dev/null)"
        if [ "$CLUSTER_UDR" == "$CURRENT_UDR" ]
        then
            echo -e "\n\n========================================================"
            echo -e "\nThe cluster UDR setup looks good now\n"
        else
            echo -e "\nScenario $LAB_SCENARIO is still FAILED\n"
        fi
    else
        echo -e "\n--> Error: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    fi
}

# Lab scenario 2
function lab_scenario_2 () {
    CLUSTER_NAME=aks-ex2-${USER_ALIAS}
    RESOURCE_GROUP=aks-ex2-rg-${USER_ALIAS}
    check_resourcegroup_cluster $RESOURCE_GROUP $CLUSTER_NAME

    az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --location $LOCATION \
    --node-count 1 \
    --generate-ssh-keys \
    --tag akslab=${LAB_SCENARIO} \
    -o table

    validate_cluster_exists $RESOURCE_GROUP $CLUSTER_NAME
    
    VM_NAME=testvm1-${USER_ALIAS}
    VM_RESOURCE_GROUP=vm-test-rg-${USER_ALIAS}
    MC_RESOURCE_GROUP=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query nodeResourceGroup -o tsv)
    #SUBNET_ID=$(az network vnet list -g $MC_RESOURCE_GROUP --query '[].subnets[].id' -o tsv)
    SUBNET_NAME=$(az network vnet list -o table | grep $MC_RESOURCE_GROUP | awk '{print $1}')
    SUBNET_ID=$(az network vnet show -g $MC_RESOURCE_GROUP -n $SUBNET_NAME --query subnets[].id -o tsv)

    az group create --name $VM_RESOURCE_GROUP --location $LOCATION
    az vm create \
    -g $VM_RESOURCE_GROUP \
    -n $VM_NAME \
    --image UbuntuLTS \
    --size Standard_B1s \
    --subnet $SUBNET_ID \
    --admin-username azureuser \
    --generate-ssh-keys \
    --tag akslab=${LAB_SCENARIO} \
    -o table

    az group delete -g $RESOURCE_GROUP -y --no-wait
    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"
    echo -e "\n\n********************************************************"
    echo -e "\nIt seems cluster is stuck in delete state...\n"
    echo -e "Cluster uri == ${CLUSTER_URI}\n"
}

# Lab scenario 3
function lab_scenario_3 () {
    CLUSTER_NAME=aks-ex3-${USER_ALIAS}
    RESOURCE_GROUP=aks-ex3-rg-${USER_ALIAS}
    VNET_NAME=aks-vnet-ex3-${USER_ALIAS}
    SUBNET_NAME=aks-subnet-ex3-${USER_ALIAS}
    check_resourcegroup_cluster $RESOURCE_GROUP $CLUSTER_NAME

    az network vnet create \
    --resource-group $RESOURCE_GROUP \
    --name $VNET_NAME \
    --address-prefixes 192.168.0.0/16 \
    --dns-servers 172.20.50.2 \
    --subnet-name $SUBNET_NAME \
    --subnet-prefix 192.168.100.0/24 \
    -o table
	
    SUBNET_ID=$(az network vnet subnet list \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --query [].id --output tsv)

    az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --location $LOCATION \
    --node-count 2 \
    --node-osdisk-size 50 \
    --node-vm-size Standard_B2s \
    --network-plugin azure \
    --service-cidr 10.0.0.0/16 \
    --dns-service-ip 10.0.0.10 \
    --docker-bridge-address 172.17.0.1/16 \
    --vnet-subnet-id $SUBNET_ID \
    --generate-ssh-keys \
    --tag akslab=${LAB_SCENARIO} \
    -o table

    validate_cluster_exists $RESOURCE_GROUP $CLUSTER_NAME

    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"
    echo "Cluster deployment failed...\n"
    echo -e "\nCluster uri == ${CLUSTER_URI}\n"
}

#if -h | --help option is selected usage will be displayed
if [ $HELP -eq 1 ]
then
	echo -e "aks-flp-networking usage: aks-flp-networking -l <LAB#> -u <USER_ALIAS>[-v|--validate] [-r|--region] [-h|--help] [--version]\n"
    echo -e "\nHere is the list of current labs available:\n
***************************************************************
*\t 1. Pods on different nodes not able to reach each other
*\t 2. Outbound issue
*\t 3. Inbound issue
***************************************************************\n"
    echo -e '"-l|--lab" Lab scenario to deploy (3 possible options)
"-r|--region" region to create the resources
"--version" print version of aks-flp-networking
"-h|--help" help info\n'
	exit 0
fi

if [ $VERSION -eq 1 ]
then
	echo -e "$SCRIPT_VERSION\n"
	exit 0
fi

if [ -z $LAB_SCENARIO ]; then
	echo -e "Error: Lab scenario value must be provided. \n"
	echo -e "aks-flp-networking usage: aks-flp-networking -l <LAB#> -u <USER_ALIAS>[-v|--validate] [-r|--region] [-h|--help] [--version]\n"
    echo -e "\nHere is the list of current labs available:\n
***************************************************************
*\t 1. Pods on different nodes not able to reach each other
*\t 2. Outbound issue
*\t 3. Inbound issue
***************************************************************\n"
	exit 9
fi

if [ -z $USER_ALIAS ]; then
	echo -e "Error: User alias value must be provided. \n"
	echo -e "aks-flp-networking usage: aks-flp-networking -l <LAB#> -u <USER_ALIAS>[-v|--validate] [-r|--region] [-h|--help] [--version]\n"
    echo -e "\nHere is the list of current labs available:\n
***************************************************************
*\t 1. Pods on different nodes not able to reach each other
*\t 2. Outbound issue
*\t 3. Inbound issue
***************************************************************\n"
	exit 10
fi

# lab scenario has a valid option
if [[ ! $LAB_SCENARIO =~ ^[1-3]+$ ]];
then
    echo -e "\nError: invalid value for lab scenario '-l $LAB_SCENARIO'\nIt must be value from 1 to 3\n"
    exit 11
fi

# main
echo -e "\n--> AKS Troubleshooting sessions
********************************************

This tool will use your default subscription to deploy the lab environments.
Verifing if you are authenticated already...\n"

# Verify az cli has been authenticated
az_login_check

if [ $LAB_SCENARIO -eq 1 ] && [ $VALIDATE -eq 0 ]
then
    check_resourcegroup_cluster
    lab_scenario_1

elif [ $LAB_SCENARIO -eq 1 ] && [ $VALIDATE -eq 1 ]
then
    lab_scenario_1_validation

elif [ $LAB_SCENARIO -eq 2 ] && [ $VALIDATE -eq 0 ]
then
    check_resourcegroup_cluster
    lab_scenario_2

elif [ $LAB_SCENARIO -eq 2 ] && [ $VALIDATE -eq 1 ]
then
    lab_scenario_2_validation

elif [ $LAB_SCENARIO -eq 3 ] && [ $VALIDATE -eq 0 ]
then
    check_resourcegroup_cluster
    lab_scenario_3

elif [ $LAB_SCENARIO -eq 3 ] && [ $VALIDATE -eq 1 ]
then
    lab_scenario_3_validation
else
    echo -e "\n--> Error: no valid option provided\n"
    exit 12
fi

exit 0