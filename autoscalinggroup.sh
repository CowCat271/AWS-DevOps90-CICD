lt_name="${env}-faresahmed-srv2-lt"
asg_name="${env}-faresahmed-srv02-asg"
elb_name="${env}-faresahmed-autoscaling-nlb"
asg_name="${env}-faresahmed-autoscaling-tg"


get_ami_id() {
    # find latest ubuntu amis (https://documentation.ubuntu.com/aws/aws-how-to/instances/find-ubuntu-images/)
    ami_id=$(aws ssm get-parameters --names /aws/service/canonical/ubuntu/server/noble/stable/current/amd64/hvm/ebs-gp3/ami-id \
            --query "Parameters[0].Value" --output text)
    
    echo "The Ubuntu AMI ID in region $region is: $ami_id"
}

prepare_lt_json() {
    echo "Preparing Launch Template json file ..."
    userdata=$(< ./launch_template/build.sh)
    
    # ${var//original_subsctring/new_substring} "//" for replacing all occurrences
    userdata=${userdata//\{region\}/$region}
    userdata=$(echo "$userdata" | base64 -w 0) # -w 0 to disable line wrapping and make it one line

    lt_json=$(< ./launch_template/launch_template.json)
    
    # ${var/original_subsctring/new_substring}
    lt_json=${lt_json/\{key_name\}/$key_name}
    lt_json=${lt_json/\{ami_id\}/$ami_id}
    lt_json=${lt_json/\{sg_id\}/$sg_id}
    lt_json=${lt_json/\{userdata\}/$userdata}

    # lt_json=$(echo "$lt_json" |  tr -d '\n' | tr -d ' ')

    #echo $lt_json
    echo "Launch Template json is ready."
}

create_lt() {
    lt_id=$(aws ec2 describe-launch-templates --region $region \
    --filters Name=launch-template-name,Values=${lt_name} \
    | grep -oP '(?<="LaunchTemplateId": ")[^"]*')

    if [ "$lt_id" == "" ]; then
        echo "Launch Template will be created..."

        prepare_lt_json

        lt_id=$(aws ec2 create-launch-template --region $region \
            --launch-template-name ${lt_name} \
            --launch-template-data "$lt_json" \
            | grep -oP '(?<="LaunchTemplateId": ")[^"]*')
        if [ "$lt_id" == "" ]; then
            echo "ERROR: couldn't create the launch template."
            exit 1
        fi
    else
        echo "Launch Template already exists."
    fi
    echo $lt_id
}

########################################################################################3

create_elb() {

    check_elb=$(aws elbv2 describe-load-balancers --region $region --query "LoadBalancers[?LoadBalancerName == '$elb_name']")
    
    if [ "$check_elb" == "[]" ]; then
        
        echo "elb will be created"
        
        check_elb=$(aws elbv2 create-load-balancer --name $elb_name --type network \
            --subnets $subnets_ids_space --security-groups $sg_id)
        if [[ $check_elb != *"LoadBalancerArn"* ]]; then
            echo "Error in creating the elb"
            exit 1
        fi
    else
        echo "elb already exist"
    fi

    elb_arn=$(echo "$check_elb" | grep -oP '(?<="LoadBalancerArn": ")[^"]*')
    
    elb_dns_name=$(echo "$check_elb" | grep -oP '(?<="DNSName": ")[^"]*')
    echo $elb_dns_name

    elb_hostedzone_id=$(echo "$check_elb" | grep -oP '(?<="CanonicalHostedZoneId": ")[^"]*')
    echo $elb_hostedzone_id
}

create_target_group() {
    tg_arn=$(aws elbv2 describe-target-groups --region $region \
        --query "TargetGroups[?TargetGroupName == '$asg_name']" | grep -oP '(?<="TargetGroupArn": ")[^"]*')

    if [ "$tg_arn" == "" ]; then
        
        echo "target group will be created"

        tg_arn=$(aws elbv2 create-target-group --name $asg_name \
            --protocol TCP --port 8002 --vpc-id $vpc_id \
            --health-check-interval-seconds 60 \
            --health-check-timeout-seconds 20 \
            --healthy-threshold-count 2 \
            --unhealthy-threshold-count 3 \
            | grep -oP '(?<="TargetGroupArn": ")[^"]*')
        
        if [ "$tg_arn" == "" ]; then
            echo "ERROR: couldn't create the target group"
            exit 1
        fi
    else
        echo "target group already exist"
    fi

    echo $tg_arn
}

create_listener() {
    ls_arn=$(aws elbv2 create-listener --load-balancer-arn "$elb_arn" \
            --protocol TCP --port 80 \
            --default-actions Type=forward,TargetGroupArn="$tg_arn" | grep -oP '(?<="ListenerArn": ")[^"]*')
    if [ "$ls_arn" == "" ]; then
        echo "ERROR: couldn't create the listener"
        exit 1
    fi
    echo $ls_arn
}

create_auto_scaling_group() {

    asg_arn=$(aws autoscaling describe-auto-scaling-groups --region $region \
            --query "AutoScalingGroups[?AutoScalingGroupName == '${asg_name}']" | grep -oP '(?<="AutoScalingGroupARN": ")[^"]*')

    if [ "$asg_arn" == "" ]; then
        
        echo "asg will be created!"
        
        aws autoscaling create-auto-scaling-group \
            --auto-scaling-group-name $asg_name \
            --launch-template LaunchTemplateId=$lt_id \
            --target-group-arns $tg_arn \
            --min-size 2 \
            --desired-capacity 2 \
            --max-size 7 \
            --vpc-zone-identifier "$subnets_ids"

            # --health-check-type ELB \
            # --health-check-grace-period 120 \ no health check for better life ._.

            asg_arn=$(aws autoscaling describe-auto-scaling-groups --region $region \
            --query "AutoScalingGroups[?AutoScalingGroupName == '${asg_name}']" | grep -oP '(?<="AutoScalingGroupARN": ")[^"]*')

            if [ "$asg_arn" == "" ]; then
                echo "Error in create the auto scaling group"
                exit 1
            fi

        echo "asg creation done. kinldy check it from the aws console!"

    else
        echo "asg already exist"
    fi

    echo $asg_name
    echo $asg_arn
}

attach_scaling_policy() {
    config=$(cat << EOF
{
    "TargetValue": 50,
    "PredefinedMetricSpecification": {
         "PredefinedMetricType": "ASGAverageCPUUtilization"
    }
}
EOF
)
    config=$(echo $config | tr -d '\n' | tr -d ' ')

    aws autoscaling put-scaling-policy --auto-scaling-group-name $asg_name \
        --policy-name cpu50-target-tracking-scaling-policy \
        --policy-type TargetTrackingScaling \
        --target-tracking-configuration $config
}



get_ami_id

create_lt

create_elb
create_target_group
create_listener

create_auto_scaling_group
attach_scaling_policy
echo