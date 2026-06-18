#!/bin/bash

env=$1

case $env in 
    qc)
        echo "load QC configuration..."
        ;;
    prod)
        echo "load Production configuration..."
        ;;
    *)
        echo "UNKNOWN ENV!"
        exit 1
        ;;
esac

if [[ ! -r "./conf-$env.sh" ]]; then
    echo "ERROR: configuration file for $env not found."
    exit 1
fi

source ./conf-$env.sh

echo $region
echo $network_cidr

source ./vpc.sh
source ./security.sh
source ./autoscalinggroup.sh
source ./dns.sh