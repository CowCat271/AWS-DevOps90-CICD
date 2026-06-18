#!/bin/bash

vpc_name="$env-faresahmed-vpc"
igw_name="$env-faresahmed-igw"
public_rtb_name="${env}-public-faresahmed-rtb"
private_rtb_name="${env}-private-faresahmed-rtb"

change_private_table_name() {
    private_rtb_id=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$vpc_id | grep -oP '(?<="RouteTableId": ")[^"]*' | uniq)

    aws ec2 create-tags --resources $private_rtb_id --tags Key=Name,Value="$private_rtb_name"
}

create_vpc() {
    vpc_id=$(aws ec2 describe-vpcs --region $region --filters Name=tag:Name,Values=$vpc_name | grep -oP '(?<="VpcId": ")[^"]*')

    if [[ "$vpc_id" == "" ]]; then
        echo "Creating VPC..."

        vpc_result=$(aws ec2 create-vpc \
            --cidr-block $network_cidr --region $region \
            --tag-specification ResourceType=vpc,Tags="[{Key=Name,Value=${vpc_name}}]" \
            --output json
            )

        echo $vpc_result

        vpc_id=$(echo "$vpc_result" | grep -oP '(?<="VpcId": ")[^"]*')

        if [[ "$vpc_id" == "" ]]; then
            echo "ERROR: couldn't create the vpc"
            exit 1
        fi
        
        change_private_table_name

        echo "VPC created"
    else
        echo "VPC already exist"
    fi

    echo "VPC ID: $vpc_id"
    echo "-------------------------------"
    echo
}

#############################################################

create_internet_gateway() {

    igw_id=$(aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=${igw_name}" | grep -oP '(?<="InternetGatewayId": ")[^"]*')

    if [[ "$igw_id" == "" ]]; then
        echo "Creating Internet gateway..."

        igw_id=$(aws ec2 create-internet-gateway --region $region \
            --tag-specification ResourceType=internet-gateway,Tags="[{Key=Name,Value=${igw_name}}]" \
            --output json | grep -oP '(?<="InternetGatewayId": ")[^"]*'
        )

        if [[ "$igw_id" == "" ]]; then
            echo "ERROR: internet gateway couldn't be created"
            exit 1
        fi


        echo "Internet Gateway created"
    else
        echo "Internet Gateway already exist"
    fi

    echo "Internet Gateway ID: $igw_id"
    echo "-------------------------------"
    echo
}

attach_ig_to_vpc() {
    igw_attach=$(aws ec2 describe-internet-gateways --internet-gateway-ids $igw_id | grep -oP '(?<="VpcId": ")[^"]*')

    if [[ "$igw_attach" != "$vpc_id" ]]; then
        echo "Attaching the gateway to the VPC"

        attach_result=$(aws ec2 attach-internet-gateway --internet-gateway-id $igw_id --vpc-id $vpc_id)

        # did it attach or not
        if [ "$attach_result" == "" ]; then
            echo "Internet gateway attached to the vpc"
        else 
            echo "Internet gateway Already Associated"
            echo "$attach_result"
        fi

    else
        echo "Internet Gateway already attached to the VPC"
    fi
    
    echo "---------------------------------------"
    echo 
}

####################################################

create_private_table() {
    private_rtb_id=$(aws ec2 describe-route-tables --filters Name=tag:Name,Values=$private_rtb_name | grep -oP '(?<="RouteTableId": ")[^"]*'  | uniq)

    if [[ "$private_rtb_id" == "" ]]; then
        echo "Private table will be created..."

        private_rtb_id=$(aws ec2 create-route-table --vpc-id $vpc_id \
            --tag-specifications ResourceType=route-table,Tags="[{Key=Name,Value=${private_rtb_name}}]" \
            --output json | grep -oP '(?<="RouteTableId": ")[^"]*'  | uniq
            )

        if [[ "$private_rtb_id" == "" ]]; then
            echo "ERROR: couldn't created private table"
            exit 1
        fi

        echo "Private table created"
    else
        echo "Private table already exist"
    fi

    echo "Private Table ID: $private_rtb_id"
    echo "---------------------------------------"
    echo 
}

########################################################

add_public_route() {
    route_result=$(aws ec2 create-route --route-table-id $public_rtb_id \
        --destination-cidr-block 0.0.0.0/0 --gateway-id $igw_id
    )
    echo $route_result  # { "Return": true }

    route_result=$(echo $route_result | jq '.Return')

    if [[ "$route_result" != "true" ]]; then
        echo "ERROR: public route couldn't be created"
        exit 1
    fi

    echo "public route created"
}

create_public_table() {
    check_rtb=$(aws ec2 describe-route-tables --filters Name=tag:Name,Values=$public_rtb_name)
    public_rtb_id=$(echo $check_rtb | grep -oP '(?<="RouteTableId": ")[^"]*'  | uniq)

    if [[ "$public_rtb_id" == "" ]]; then
        echo "public table will be created..."

        public_rtb_id=$(aws ec2 create-route-table --vpc-id $vpc_id \
            --tag-specifications ResourceType=route-table,Tags="[{Key=Name,Value=${public_rtb_name}}]" \
            --output json | grep -oP '(?<="RouteTableId": ")[^"]*'  | uniq
        )

        if [[ "$public_rtb_id" == "" ]]; then
            echo "ERROR: couldn't created public table"
            exit 1
        fi

        echo "public table created"

        add_public_route
    else
        echo "public table already exist"

        rtb_route=$(echo $check_rtb | grep -oP '"DestinationCidrBlock"\s*:\s*"0.0.0.0/0"')
        if [[ "$rtb_route" == "" ]]; then
            add_public_route
        else
            echo "public route already exist"
        fi

    fi

    echo "Public Table ID: $public_rtb_id"
    echo "---------------------------------------"
    echo 
}

########################################################

create_subnet() {
    # $1 AZ, $2 subnet cidr, $3 public/private

    subnet_name="$env-sub-$3-$1"
    subnet_id=$(aws ec2 describe-subnets --region $region --filters Name=tag:Name,Values=$subnet_name | grep -oP '(?<="SubnetId": ")[^"]*')

    if [[ "$subnet_id" == "" ]]; then
        echo "Creating subnet ($subnet_name)..."

        subnet_id=$(aws ec2 create-subnet \
            --vpc-id $vpc_id --availability-zone ${region}$1 --cidr-block $2 \
            --tag-specification ResourceType=subnet,Tags="[{Key=Name,Value=${subnet_name}}]" --output json \
            | grep -oP '(?<="SubnetId": ")[^"]*'
        )

        if [[ "$subnet_id" == "" ]]; then
            echo "ERROR: Subnet ($subnet_name) couldn't be created"
            exit 1
        fi

        echo "Subnet ($subnet_name) created"
    else
        echo "Subnet ($subnet_name) already exist"
    fi

    echo "Subnet ID: $subnet_id"
}

create_public_subnets() {
    subnets_ids=""
    subnets_ids_space=""

    for sub in "${public_subnets[@]}"; do
        readarray -d "-" -t sub_array <<< "$sub"
        create_subnet ${sub_array[1]} ${sub_array[0]} public

        aws ec2 associate-route-table --route-table-id $public_rtb_id --subnet-id $subnet_id
        
        subnets_ids+="$subnet_id,"
        subnets_ids_space+="$subnet_id "
        echo "---------------------------------------"
        echo 
    done

    subnets_ids=${subnets_ids%,}
    subnets_ids_space=${subnets_ids_space% }
}

create_private_subnets() {
    for sub in "${private_subnets[@]}"; do
        readarray -d "-" -t sub_array <<< "$sub"
        create_subnet ${sub_array[1]} ${sub_array[0]} private
        aws ec2 associate-route-table --route-table-id $private_rtb_id --subnet-id $subnet_id
        echo "---------------------------------------"
        echo 
    done
}

##########################################################

create_vpc

create_internet_gateway
attach_ig_to_vpc

create_private_table
create_public_table

create_public_subnets
create_private_subnets




