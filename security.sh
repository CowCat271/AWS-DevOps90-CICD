key_name="${env}-faresahmed-key_ec2_ssh_real"
key_format="pem"
ec2_sg_name="${env}-faresahmed-ec2_sg"
elb_sg_name="${env}-faresahmed-elb_sg"
# security_group_name="${env}-faresahmed-main_sg"
EC2_RULES=(
    '{"IpProtocol": "tcp", "FromPort": 22, "ToPort": 22, "IpRanges": [{"CidrIp": "0.0.0.0/0", "Description": "ssh"}]}'
    '{"IpProtocol": "tcp", "FromPort": 8002, "ToPort": 8002, "UserIdGroupPairs": [{"GroupId": "<elb-security-group-id>", "Description": "allow srv02 (8002) from ELB"}]}'
)
ELB_RULES=(
    '{"IpProtocol": "tcp", "FromPort": 80, "ToPort": 80, "IpRanges": [{"CidrIp": "0.0.0.0/0", "Description": "http"}]}'
)

describe_ec2_key(){
    echo "Start describe_ec2_key ..."
    ec2_key=$(aws ec2 describe-key-pairs --key-names $key_name 2>/dev/null | grep -oP '(?<="KeyName": ")[^"]*')
    echo $ec2_key
    echo "----------------------------------------"
}

create_ec2_key(){
    echo "Start create_ec2_key ..."
    aws ec2 create-key-pair --key-name $key_name --key-type ed25519 --key-format $key_format --query 'KeyMaterial' --output text > "${key_name}.${key_format}"
    if [[ ! -f "${key_name}.${key_format}" ]]; then
        echo "ERROR: couldn't create the ec2 key."
        exit 1
    else
        echo "ec2 key is created."
    fi
    echo "----------------------------------------"
}

delete_ec2_key(){
    echo "Start delete_ec2_key ..."
    aws ec2 delete-key-pair --key-name $key_name
    echo "----------------------------------------"
}

############################################################################################################

describe_secret(){
    echo "Start describe_secret ..."
    secret_arn=$(aws secretsmanager describe-secret --secret-id $key_name 2>/dev/null | grep -oP '(?<="ARN": ")[^"]*')
    echo $secret_arn
    echo "----------------------------------------"
}

create_secret(){
    echo "Start create_secret ..."
    delete_secret

    secret_arn=$(aws secretsmanager create-secret --name $key_name --description "EC2 ssh key" --secret-string file://"${key_name}.${key_format}" | grep -oP "(?<=\"ARN\": \")[^\"]*")
    
    if [[ "$secret_arn" == "" ]]; then
        echo "ERROR: couldn't create the secret."
        exit 1
    else
        echo "Secret key is created."
        echo $secret_arn
    fi
    echo "----------------------------------------"
}

delete_secret(){
    echo "Start delete_secret ..."
    aws secretsmanager delete-secret --secret-id $key_name --force-delete-without-recovery  | grep -oP '(?<="ARN": ")[^"]*'
    echo "----------------------------------------"
}

####################################################################################################


create_elb_sg(){
    echo "Start create_elb_sg ..."

    elb_sg_id=$(aws ec2 describe-security-groups \
            --filters Name=group-name,Values=${elb_sg_name} | grep -oP '(?<="GroupId": ")[^"]*' | uniq)

    if [[ "$elb_sg_id" == "" ]]; then
        
        echo "ELB Security Group will be created"

        elb_sg_id=$(aws ec2 create-security-group --group-name ${elb_sg_name} \
        --vpc-id $vpc_id --description 'ELB Security Group' )
        
        echo $elb_sg_id

        elb_sg_id=$(echo "$elb_sg_id"| grep -oP '(?<="GroupId": ")[^"]*' | uniq)
        if [[ "$elb_sg_id" == "" ]]; then
            echo "ERROR: couldn't create the ELB security group."
            exit 1
        fi

        echo $elb_sg_id

        for elb_rule in "${ELB_RULES[@]}"; do
            echo "Adding elb rule: $elb_rule"
            ADD_RULE_OUTPUT=$(aws ec2 authorize-security-group-ingress --group-id $elb_sg_id --ip-permissions "$elb_rule" 2>&1)

            if [[ $? -ne 0 ]]; then
                echo "ERROR: adding elb rule '$elb_rule': $ADD_RULE_OUTPUT"
                echo "deleting the elb security group ..."
                aws ec2 delete-security-group --group-id $elb_sg_id
                exit 1
            fi
        done

    else
        echo "ELB Security group already exist"
        echo $elb_sg_id
    fi
    echo "----------------------------------------"
}


create_ec2_sg(){
    echo "Start create_ec2_sg ..."

    ec2_sg_id=$(aws ec2 describe-security-groups \
            --filters Name=group-name,Values=${ec2_sg_name} | grep -oP '(?<="GroupId": ")[^"]*' | uniq)

    if [[ "$ec2_sg_id" == "" ]]; then
        
        echo "EC2 Security Group will be created"

        ec2_sg_id=$(aws ec2 create-security-group --group-name ${ec2_sg_name} \
        --vpc-id $vpc_id --description 'EC2 Main Security Group' )
        
        echo $ec2_sg_id

        ec2_sg_id=$(echo "$ec2_sg_id"| grep -oP '(?<="GroupId": ")[^"]*' | uniq)
        if [[ "$ec2_sg_id" == "" ]]; then
            echo "ERROR: couldn't create the ec2 security group."
            exit 1
        fi

        echo $ec2_sg_id

        for ec2_rule in "${EC2_RULES[@]}"; do
            # ${var/original_subsctring/new_substring}
            ec2_rule=${ec2_rule/<elb-security-group-id>/$elb_sg_id}

            echo "Adding ec2 rule: $ec2_rule"
            ADD_RULE_OUTPUT=$(aws ec2 authorize-security-group-ingress --group-id $ec2_sg_id --ip-permissions "$ec2_rule" 2>&1)

            if [[ $? -ne 0 ]]; then
                echo "ERROR: adding ec2 sg rule '$rule': $ADD_RULE_OUTPUT"
                echo "deleting the ec2 security group ..."
                aws ec2 delete-security-group --group-id $ec2_sg_id
                exit 1
            fi
        done

    else
        echo "EC2 Security group already exist"
        echo $ec2_sg_id
    fi
    echo "----------------------------------------"
}


# create ec2 kay and store it in a secret
describe_ec2_key
if [[ "$ec2_key" == "" ]]; then
    echo "key is not exists."
    echo "Create key and secret."
    create_ec2_key
    create_secret
else
    describe_secret
    if [[ "$secret_arn" == "" ]]; then
        echo "key exists but secret not exists."
        echo "Deleting everything then create new key and secret."
        delete_ec2_key
        create_ec2_key
        create_secret
    else
        echo "Nothing created. key and secret are already exists."
        echo "----------------------------------------"
    fi
fi

# create the security group
create_elb_sg
create_ec2_sg
echo
